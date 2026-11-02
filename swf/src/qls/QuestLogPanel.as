package qls
{
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.geom.Rectangle;
	import flash.text.TextField;
	import flash.text.TextFieldType;
	import flash.ui.Keyboard;

	/**
	 * Collapsible, grouped quest log.
	 *
	 *   Section  (source plugin: Main Game / Far Harbor / Nuka-World / a mod)
	 *     Line   (questline: Main Story / Brotherhood of Steel / Companions)
	 *       Quest
	 *         Objective
	 *
	 * All quest data comes from the F4SE plugin in one call on open; filtering,
	 * collapsing and scrolling happen entirely here so typing in the search box
	 * never touches native code.
	 */
	public class QuestLogPanel extends Sprite
	{
		private static const STATUS_RUNNING:int = 0;
		private static const STATUS_COMPLETED:int = 1;
		private static const STATUS_FAILED:int = 2;

		private var _plugin:Object;
		private var _host:Object;
		private var _bridge:Object;

		private var _tree:Array = [];        // raw sections from the plugin
		private var _rows:Array = [];        // flattened, filtered view model
		private var _pool:Array = [];        // recycled RowViews
		private var _questOpen:Object = {};  // formID -> objectives expanded
		private var _query:String = "";
		private var _showFinished:Boolean = true;

		private var _viewport:Sprite;
		private var _viewportMask:Shape;
		private var _viewHeight:Number = 400;
		private var _scrollbar:Shape;
		private var _search:TextField;
		private var _hint:TextField;
		private var _empty:TextField;

		private var _width:Number = 420;
		private var _height:Number = 460;
		private var _scroll:Number = 0;
		private var _selected:int = -1;
		private var _lastClickTime:Number = 0;
		private var _lastClickRow:int = -1;

		public function QuestLogPanel()
		{
			_viewport = new Sprite();
			addChild(_viewport);

			// Clip with a mask, not scrollRect. Scaleform's AS3 support for
			// scrollRect is unreliable; masks are core Flash and always work.
			_viewportMask = new Shape();
			addChild(_viewportMask);
			_viewport.mask = _viewportMask;

			_scrollbar = new Shape();
			addChild(_scrollbar);

			_search = new TextField();
			_search.type = TextFieldType.INPUT;
			_search.embedFonts = Style.EMBED_FONTS;
			_search.multiline = false;
			_search.background = false;
			_search.border = false;
			_search.addEventListener(Event.CHANGE, onSearchChanged);
			addChild(_search);

			_hint = new TextField();
			_hint.selectable = false;
			_hint.mouseEnabled = false;
			_hint.embedFonts = Style.EMBED_FONTS;
			addChild(_hint);

			_empty = new TextField();
			_empty.selectable = false;
			_empty.mouseEnabled = false;
			_empty.embedFonts = Style.EMBED_FONTS;
			_empty.visible = false;
			addChild(_empty);

			addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			addEventListener(Event.REMOVED_FROM_STAGE, onRemovedFromStage);
		}

		// -------------------------------------------------------------- setup

		/**
		 * Called by the shim inside PipboyMenu.swf.
		 * @param hostRoot the Pip-Boy movie root (root1), where f4se lives
		 */
		public function init(hostRoot:Object, w:Number, h:Number, bridge:Object = null):void
		{
			_host = hostRoot;
			_bridge = bridge;

			// The shim already located the plugin and hands it over, which is
			// more reliable than walking the tree from here. Fall back to the
			// walk only if it did not.
			if (bridge != null && bridge.plugin != null) {
				_plugin = bridge.plugin;
			} else {
				_plugin = findPlugin(hostRoot);
			}

			log("panel init: " + w + "x" + h);
			setSize(w, h);
			log("panel sized");
			refresh();
			log("panel refreshed, " + _rows.length + " rows");
		}

		/**
		 * F4SE registers on the top-level movie, but the object handed to us is
		 * the data page's root, one or more levels below it. Walk up until we
		 * find f4se rather than assuming which level it lives on.
		 */
		private function findPlugin(hostRoot:Object):Object
		{
			var node:Object = hostRoot;
			var depth:int = 0;
			while (node != null && depth < 12) {
				try {
					if (node.f4se != null && node.f4se.plugins != null &&
					    node.f4se.plugins.QuestLogSorter != null) {
						return node.f4se.plugins.QuestLogSorter;
					}
				} catch (error:Error) {
				}
				try {
					node = node.parent;
				} catch (parentError:Error) {
					node = null;
				}
				depth++;
			}
			return null;
		}

		public function setSize(w:Number, h:Number):void
		{
			_width = w;
			_height = h;

			_search.x = Style.PAD_X;
			_search.y = 0;
			_search.width = _width - Style.PAD_X * 2;
			_search.height = Style.SEARCH_HEIGHT;
			_search.defaultTextFormat = Style.body(13, Style.FG_DIM);
			applySearchPlaceholder();

			var top:Number = Style.SEARCH_HEIGHT + 4;
			var bottom:Number = 18;
			_viewport.y = top;
			_viewHeight = Math.max(1, _height - top - bottom);

			_viewportMask.graphics.clear();
			_viewportMask.graphics.beginFill(0x000000, 1);
			_viewportMask.graphics.drawRect(0, top, _width, _viewHeight);
			_viewportMask.graphics.endFill();

			_hint.x = Style.PAD_X;
			_hint.y = _height - bottom;
			_hint.width = _width - Style.PAD_X * 2;
			_hint.height = bottom;
			_hint.text = "ENTER track  \u2022  M map  \u2022  SPACE objectives  \u2022  \u2190/\u2192 fold";
			_hint.setTextFormat(Style.body(10, Style.FG_FAINT));

			_empty.x = Style.PAD_X;
			_empty.y = top + 20;
			_empty.width = _width - Style.PAD_X * 2;
			_empty.height = 40;

			render();
		}

		private function onAddedToStage(event:Event):void
		{
			stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, false, 0, true);
			addEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
			addEventListener(MouseEvent.CLICK, onClick);
			addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		}

		private function onRemovedFromStage(event:Event):void
		{
			if (stage) {
				stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
			}
			removeEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
			removeEventListener(MouseEvent.CLICK, onClick);
			removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
			flushState();
		}

		// --------------------------------------------------------------- data

		/** Pulls the whole tree from native and rebuilds the view. */
		public function refresh():void
		{
			if (_plugin == null) {
				_tree = [];
				log("plugin bridge missing - is QuestLogSorter.dll loaded?");
			} else {
				try {
					// The plugin hands the whole tree over as one JSON string
					// rather than thousands of native objects - one boundary
					// crossing instead of a few thousand.
					_tree = JSON.parse(_plugin.getTree(_showFinished)) as Array;
				} catch (error:Error) {
					_tree = [];
					log("getTree failed: " + error.message);
				}
			}
			if (_tree == null) {
				_tree = [];
			}
			log("getTree returned " + _tree.length + " sections");
			rebuild();
		}

		private function rebuild():void
		{
			_rows = [];

			var searching:Boolean = _query.length > 0;

			for each (var section:Object in _tree) {
				var sectionRows:Array = [];
				var sectionOpen:int = 0;

				for each (var line:Object in section.lines) {
					var quests:Array = filterQuests(line.quests as Array);
					if (quests.length == 0) {
						continue;
					}

					var lineCollapsed:Boolean = searching ? false : Boolean(line.collapsed);
					var lineRow:Object = {
						kind: RowView.KIND_LINE,
						depth: 1,
						label: String(line.name),
						meta: countLabel(quests),
						key: String(line.key),
						expandable: true,
						collapsed: lineCollapsed
					};
					sectionRows.push(lineRow);

					if (lineCollapsed) {
						continue;
					}

					for each (var quest:Object in quests) {
						var finished:Boolean = int(quest.status) != STATUS_RUNNING;
						if (!finished) {
							sectionOpen++;
						}

						var expanded:Boolean = questExpanded(quest, searching);
						sectionRows.push({
							kind: RowView.KIND_QUEST,
							depth: 2,
							label: String(quest.name),
							meta: statusLabel(quest),
							expandable: (quest.objectives as Array).length > 0,
							collapsed: !expanded,
							tracked: Boolean(quest.tracked),
							finished: finished,
							failed: int(quest.status) == STATUS_FAILED,
							formID: Number(quest.formID)
						});

						if (!expanded) {
							continue;
						}

						for each (var objective:Object in quest.objectives) {
							sectionRows.push({
								kind: RowView.KIND_OBJECTIVE,
								depth: 3,
								label: String(objective.text),
								expandable: false,
								finished: Boolean(objective.completed) || Boolean(objective.failed),
								failed: Boolean(objective.failed),
								formID: Number(quest.formID)
							});
						}
					}
				}

				if (sectionRows.length == 0) {
					continue;
				}

				var sectionCollapsed:Boolean = searching ? false : Boolean(section.collapsed);
				_rows.push({
					kind: RowView.KIND_SECTION,
					depth: 0,
					label: String(section.name).toUpperCase(),
					meta: sectionOpen > 0 ? String(sectionOpen) + " active" : "",
					key: String(section.key),
					expandable: true,
					collapsed: sectionCollapsed
				});

				if (!sectionCollapsed) {
					_rows = _rows.concat(sectionRows);
				}
			}

			if (_selected >= _rows.length) {
				_selected = _rows.length - 1;
			}
			clampScroll();
			render();
		}

		private function filterQuests(quests:Array):Array
		{
			if (quests == null) {
				return [];
			}
			if (_query.length == 0) {
				return quests;
			}
			var matched:Array = [];
			for each (var quest:Object in quests) {
				if (String(quest.search).indexOf(_query) != -1) {
					matched.push(quest);
				}
			}
			return matched;
		}

		private function questExpanded(quest:Object, searching:Boolean):Boolean
		{
			if ((quest.objectives as Array).length == 0) {
				return false;
			}
			if (searching) {
				return true;
			}
			var key:String = String(quest.formID);
			if (_questOpen.hasOwnProperty(key)) {
				return Boolean(_questOpen[key]);
			}
			// Sensible default: the quest you are actually doing is already open.
			return Boolean(quest.tracked);
		}

		private function countLabel(quests:Array):String
		{
			var open:int = 0;
			for each (var quest:Object in quests) {
				if (int(quest.status) == STATUS_RUNNING) {
					open++;
				}
			}
			if (open == quests.length) {
				return String(quests.length);
			}
			return String(open) + "/" + String(quests.length);
		}

		private function statusLabel(quest:Object):String
		{
			switch (int(quest.status)) {
				case STATUS_COMPLETED:
					return "DONE";
				case STATUS_FAILED:
					return "FAILED";
				default:
					return quest.tracked ? "TRACKING" : "";
			}
		}

		// ------------------------------------------------------------- render

		private function render():void
		{
			var viewHeight:Number = _viewHeight;
			var first:int = Math.max(0, Math.floor(_scroll / Style.ROW_HEIGHT) - 1);
			var y:Number = 0;
			var index:int = 0;
			var used:int = 0;

			// Rows are not uniform height, so walk from the top and skip what is
			// above the viewport. Cheap enough at a few hundred rows.
			while (index < _rows.length) {
				var row:Object = _rows[index];
				var h:Number = int(row.kind) == RowView.KIND_OBJECTIVE ?
					Style.OBJECTIVE_HEIGHT : Style.ROW_HEIGHT;

				if (y + h >= _scroll && y <= _scroll + viewHeight) {
					var view:RowView = viewAt(used++);
					row.selected = (index == _selected);
					view.bind(row, _width - Style.SCROLLBAR_WIDTH - 2);
					view.y = y - _scroll;
					view.visible = true;
					view.hovered = (index == _selected);
					view.name = "row" + String(index);
				}

				y += h;
				index++;

				if (y > _scroll + viewHeight) {
					break;
				}
			}

			for (var i:int = used; i < _pool.length; i++) {
				RowView(_pool[i]).visible = false;
			}

			_empty.visible = _rows.length == 0;
			if (_empty.visible) {
				_empty.text = _query.length > 0 ?
					"No quests match \u201C" + _query + "\u201D" :
					"No quests yet.";
				_empty.setTextFormat(Style.body(13, Style.FG_DIM));
			}

			drawScrollbar(contentHeight(), viewHeight);
		}

		private function viewAt(index:int):RowView
		{
			while (_pool.length <= index) {
				var view:RowView = new RowView();
				_pool.push(view);
				_viewport.addChild(view);
			}
			return _pool[index] as RowView;
		}

		private function contentHeight():Number
		{
			var total:Number = 0;
			for each (var row:Object in _rows) {
				total += int(row.kind) == RowView.KIND_OBJECTIVE ?
					Style.OBJECTIVE_HEIGHT : Style.ROW_HEIGHT;
			}
			return total;
		}

		private function drawScrollbar(content:Number, viewHeight:Number):void
		{
			_scrollbar.graphics.clear();
			if (content <= viewHeight) {
				return;
			}

			var x:Number = _width - Style.SCROLLBAR_WIDTH;
			var trackTop:Number = _viewport.y;
			var trackHeight:Number = viewHeight;

			_scrollbar.graphics.beginFill(Style.FG, 0.12);
			_scrollbar.graphics.drawRect(x, trackTop, Style.SCROLLBAR_WIDTH, trackHeight);
			_scrollbar.graphics.endFill();

			var thumbHeight:Number = Math.max(24, trackHeight * (viewHeight / content));
			var progress:Number = _scroll / (content - viewHeight);
			_scrollbar.graphics.beginFill(Style.FG, 0.55);
			_scrollbar.graphics.drawRect(
				x, trackTop + progress * (trackHeight - thumbHeight),
				Style.SCROLLBAR_WIDTH, thumbHeight);
			_scrollbar.graphics.endFill();
		}

		// -------------------------------------------------------------- input

		private function rowIndexAt(localY:Number):int
		{
			var y:Number = -_scroll;
			for (var i:int = 0; i < _rows.length; i++) {
				var h:Number = int(_rows[i].kind) == RowView.KIND_OBJECTIVE ?
					Style.OBJECTIVE_HEIGHT : Style.ROW_HEIGHT;
				if (localY >= y && localY < y + h) {
					return i;
				}
				y += h;
			}
			return -1;
		}

		private function onMouseMove(event:MouseEvent):void
		{
			var index:int = rowIndexAt(event.localY - _viewport.y);
			if (index >= 0 && index != _selected) {
				_selected = index;
				render();
			}
		}

		private function onWheel(event:MouseEvent):void
		{
			_scroll -= event.delta * Style.ROW_HEIGHT;
			clampScroll();
			render();
		}

		private function onClick(event:MouseEvent):void
		{
			var index:int = rowIndexAt(event.localY - _viewport.y);
			if (index < 0) {
				return;
			}
			_selected = index;

			var now:Number = new Date().getTime();
			var isDoubleClick:Boolean = (index == _lastClickRow) && (now - _lastClickTime < 350);
			_lastClickRow = index;
			_lastClickTime = now;

			if (isDoubleClick && int(_rows[index].kind) == RowView.KIND_QUEST) {
				trackSelected();
				return;
			}
			toggle(index);
		}

		private function onKeyDown(event:KeyboardEvent):void
		{
			// Let the search box keep normal typing.
			if (stage != null && stage.focus == _search &&
			    event.keyCode != Keyboard.ENTER && event.keyCode != Keyboard.ESCAPE) {
				return;
			}

			switch (event.keyCode) {
				case Keyboard.DOWN:
					move(1);
					break;
				case Keyboard.UP:
					move(-1);
					break;
				case Keyboard.PAGE_DOWN:
					move(10);
					break;
				case Keyboard.PAGE_UP:
					move(-10);
					break;
				case Keyboard.LEFT:
					setCollapsedAt(_selected, true);
					break;
				case Keyboard.RIGHT:
					setCollapsedAt(_selected, false);
					break;
				case Keyboard.SPACE:
					toggle(_selected);
					break;
				case Keyboard.ENTER:
					trackSelected();
					break;
				case 77: // M
					showSelectedOnMap();
					break;
				case Keyboard.ESCAPE:
					if (_query.length > 0) {
						_search.text = "";
						_query = "";
						applySearchPlaceholder();
						rebuild();
						event.stopPropagation();
					}
					break;
			}
		}

		private function move(delta:int):void
		{
			if (_rows.length == 0) {
				return;
			}
			_selected = Math.max(0, Math.min(_rows.length - 1, _selected + delta));
			scrollTo(_selected);
			render();
		}

		private function scrollTo(index:int):void
		{
			var y:Number = 0;
			for (var i:int = 0; i < index; i++) {
				y += int(_rows[i].kind) == RowView.KIND_OBJECTIVE ?
					Style.OBJECTIVE_HEIGHT : Style.ROW_HEIGHT;
			}
			var viewHeight:Number = _viewHeight;
			if (y < _scroll) {
				_scroll = y;
			} else if (y + Style.ROW_HEIGHT > _scroll + viewHeight) {
				_scroll = y + Style.ROW_HEIGHT - viewHeight;
			}
			clampScroll();
		}

		private function clampScroll():void
		{
			var max:Number = Math.max(0, contentHeight() - _viewHeight);
			_scroll = Math.max(0, Math.min(max, _scroll));
		}

		// ------------------------------------------------------------ actions

		private function toggle(index:int):void
		{
			if (index < 0 || index >= _rows.length) {
				return;
			}
			var row:Object = _rows[index];
			if (!row.expandable) {
				return;
			}
			setCollapsedAt(index, !row.collapsed);
		}

		private function setCollapsedAt(index:int, collapsed:Boolean):void
		{
			if (index < 0 || index >= _rows.length) {
				return;
			}
			var row:Object = _rows[index];
			if (!row.expandable || row.collapsed == collapsed) {
				return;
			}

			if (int(row.kind) == RowView.KIND_QUEST) {
				_questOpen[String(row.formID)] = !collapsed;
			} else {
				persistCollapsed(String(row.key), collapsed);
				applyCollapsed(String(row.key), collapsed);
			}
			rebuild();
		}

		/** Mirror the change into the raw tree so rebuild() sees it. */
		private function applyCollapsed(key:String, collapsed:Boolean):void
		{
			for each (var section:Object in _tree) {
				if (String(section.key) == key) {
					section.collapsed = collapsed;
					return;
				}
				for each (var line:Object in section.lines) {
					if (String(line.key) == key) {
						line.collapsed = collapsed;
						return;
					}
				}
			}
		}

		/**
		 * Tracking goes through the game's own path, not the plugin. QuestsTab
		 * in Pipboy_DataPage.swf uses exactly this call, so our tree behaves
		 * identically to the stock list. The shim supplies QLS_engineCall.
		 */
		private function trackSelected():void
		{
			var quest:Object = selectedQuest();
			if (quest == null) {
				return;
			}
			if (engineCall("setQuestActive", quest.formID)) {
				// The plugin re-reads the tracked flag off the quest record,
				// so a refresh shows whatever the engine actually did.
				refresh();
			}
		}

		/**
		 * The two engine actions are separate hooks rather than one generic
		 * call, because the vanilla code passes different things to each:
		 * SetQuestActive gets the list entry object, ShowQuestOnMap gets the
		 * bare formID. The shim owns that difference.
		 *
		 * Single exit: ASC does not treat a trailing try/catch as covering
		 * every return path, even when both branches return.
		 */
		private function engineCall(hook:String, formID:Number):Boolean
		{
			if (_bridge == null || _bridge[hook] == null) {
				log("no engine bridge - " + hook + " ignored");
				return false;
			}
			var ok:Boolean = false;
			try {
				ok = Boolean(_bridge[hook](formID));
			} catch (error:Error) {
				log(hook + " failed: " + error.message);
			}
			return ok;
		}

		private function showSelectedOnMap():void
		{
			var quest:Object = selectedQuest();
			if (quest == null) {
				return;
			}
			// The same engine call the vanilla "Show on Map" button makes -
			// it handles tracking and the page switch together.
			engineCall("showQuestOnMap", quest.formID);
		}

		private function selectedQuest():Object
		{
			if (_selected < 0 || _selected >= _rows.length) {
				return null;
			}
			var row:Object = _rows[_selected];
			var formID:Number = Number(row.formID);
			if (isNaN(formID)) {
				return null;
			}
			for each (var section:Object in _tree) {
				for each (var line:Object in section.lines) {
					for each (var quest:Object in line.quests) {
						if (Number(quest.formID) == formID) {
							return quest;
						}
					}
				}
			}
			return null;
		}

		// ------------------------------------------------------------- search

		private function onSearchChanged(event:Event):void
		{
			_query = _search.text.toLowerCase();
			_scroll = 0;
			rebuild();
		}

		private function applySearchPlaceholder():void
		{
			if (_search.text.length == 0) {
				_search.text = "";
			}
			_search.setTextFormat(Style.body(13, Style.FG));
		}

		// -------------------------------------------------------------- misc

		private function persistCollapsed(key:String, collapsed:Boolean):void
		{
			if (_plugin == null) {
				return;
			}
			try {
				_plugin.setCollapsed(key, collapsed);
			} catch (error:Error) {
				// non-fatal: state just will not survive a restart
			}
		}

		private function flushState():void
		{
			if (_plugin == null) {
				return;
			}
			try {
				_plugin.flushState();
			} catch (error:Error) {
			}
		}

		private function log(message:String):void
		{
			if (_plugin == null) {
				return;
			}
			try {
				_plugin.log(message);
			} catch (error:Error) {
			}
		}
	}
}
