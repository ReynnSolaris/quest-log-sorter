package qls
{
	import flash.display.DisplayObject;
	import flash.display.Loader;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.net.URLRequest;
	import flash.system.ApplicationDomain;
	import flash.system.LoaderContext;

	import Shared.BGSExternalInterface;

	/**
	 * Paste into Pipboy_DataPage.swf with JPEXS as class `qls.QLSShim`,
	 * against the Existing DoABC tag.
	 *
	 * Written for JPEXS's AS3 compiler, not mxmlc:
	 *   - no closures, no `for each`, no getters, no default parameters
	 *   - every member access on an untyped object uses brackets, because
	 *     JPEXS resolves dotted names at compile time even on Object and
	 *     fails on any name that collides with something package-internal
	 *
	 * INSTRUMENTED. Every step logs to QuestLogSorter.log via the plugin, so a
	 * hard crash tells you exactly which call faulted by what the last line is.
	 * An uncaught AS3 error under Scaleform kills the process instead of
	 * raising anything catchable, so the log is the only witness.
	 */
	public class QLSShim
	{
		private static const SWF_PATH:String = "QuestLogSorter/QLS.swf";

		/**
		 * Bisect switch. Set false and re-save the SWF: attach then logs and
		 * returns without creating a Loader. If the crash goes away, it is the
		 * load or QLS.swf. If it persists, the crash is in the QuestsTab edits
		 * themselves and nothing here is involved.
		 */
		private static const ENABLE_LOAD:Boolean = true;

		private static var _loader:Loader = null;
		private static var _panel:Object = null;
		private static var _tab:Object = null;
		private static var _container:Sprite = null;
		private static var _host:Object = null;
		private static var _plugin:Object = null;

		private static var _x:Number = 0;
		private static var _y:Number = 0;
		private static var _w:Number = 0;
		private static var _h:Number = 0;

		// --- logging ---------------------------------------------------------

		/**
		 * F4SE hangs its registry off the top-level movie, which is above the
		 * data page. Walk up until we find it rather than assuming a level.
		 */
		private static function findPlugin(start:Object):Object
		{
			var node:Object = start;
			var depth:int = 0;
			while (node != null && depth < 16) {
				try {
					if (node["f4se"] != null) {
						if (node["f4se"]["plugins"] != null) {
							if (node["f4se"]["plugins"]["QuestLogSorter"] != null) {
								return node["f4se"]["plugins"]["QuestLogSorter"];
							}
						}
					}
				} catch(e:Error) {
				}
				try {
					node = node["parent"];
				} catch(e2:Error) {
					node = null;
				}
				depth = depth + 1;
			}
			return null;
		}

		public static function say(message:String):void
		{
			try {
				if (_plugin != null) {
					_plugin["log"]("[shim] " + message);
				}
			} catch(e:Error) {
			}
		}

		// --- attach ----------------------------------------------------------

		public static function attach(tab:Sprite, hostRoot:Object,
			px:Number, py:Number, pw:Number, ph:Number):void
		{
			_container = tab;
			_tab = tab;
			_host = hostRoot;
			_x = px;
			_y = py;
			_w = pw;
			_h = ph;

			if (_plugin == null) {
				_plugin = QLSShim.findPlugin(tab);
			}
			if (_plugin == null) {
				_plugin = QLSShim.findPlugin(hostRoot);
			}

			QLSShim.say("attach entered, bounds " + px + "," + py + " " + pw + "x" + ph);

			if (_plugin == null) {
				// Nothing will be logged from here on. Say so where we still can.
				return;
			}

			if (_panel != null) {
				QLSShim.say("already attached, repositioning");
				QLSShim.position();
				try {
					_panel["refresh"]();
				} catch(eRefresh:Error) {
					QLSShim.say("refresh threw: " + eRefresh.message);
				}
				return;
			}

			if (!ENABLE_LOAD) {
				QLSShim.say("ENABLE_LOAD is false - not loading");
				return;
			}

			try {
				_loader = new Loader();
				QLSShim.say("loader created");

				_loader.contentLoaderInfo.addEventListener(Event.COMPLETE, QLSShim.onLoaded);
				_loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, QLSShim.onLoadError);
				QLSShim.say("listeners attached");

				// Vanilla never calls load() bare - updateQuestAnimation always
				// passes LoaderContext(false, ApplicationDomain.currentDomain).
				var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
				QLSShim.say("calling load " + SWF_PATH);
				_loader.load(new URLRequest(SWF_PATH), ctx);
				QLSShim.say("load returned");
			}
			catch(eLoad:Error) {
				QLSShim.say("load threw: " + eLoad.message);
				_loader = null;
			}
		}

		public static function refresh():void
		{
			if (_panel == null) {
				return;
			}
			try {
				_panel["refresh"]();
			} catch(e:Error) {
				QLSShim.say("refresh threw: " + e.message);
			}
		}

		public static function detach():void
		{
			if (_panel == null) {
				return;
			}
			try {
				var disp:DisplayObject = DisplayObject(_panel);
				if (disp.parent != null) {
					disp.parent.removeChild(disp);
				}
			} catch(e:Error) {
			}
		}

		// --- load completion --------------------------------------------------

		private static function onLoaded(event:Event):void
		{
			QLSShim.say("onLoaded entered");
			try {
				_panel = _loader.content;
			} catch(eContent:Error) {
				QLSShim.say("reading content threw: " + eContent.message);
				return;
			}

			if (_panel == null) {
				QLSShim.say("content was null");
				return;
			}
			QLSShim.say("content obtained");

			// Add the CONTENT, never the Loader. Vanilla does the same:
			// redrawUIComponent adds Quest_VaultBoyLoader.contentLoaderInfo.content
			// and never puts the Loader itself on the display list.
			try {
				_container.addChild(DisplayObject(_panel));
				QLSShim.say("addChild ok");
			} catch(eAdd:Error) {
				QLSShim.say("addChild threw: " + eAdd.message);
				return;
			}

			QLSShim.position();
			QLSShim.say("positioned");

			// Object literals are dynamic, so adding members is always safe.
			// Never hang these off the movie root: that is a compiled class
			// instance and therefore sealed, and assigning an undeclared
			// property throws ReferenceError #1056 - which under Scaleform
			// takes the game down rather than surfacing as a catchable error.
			var bridge:Object = {};
			bridge["setQuestActive"] = QLSShim.setQuestActive;
			bridge["showQuestOnMap"] = QLSShim.showQuestOnMap;
			bridge["plugin"] = _plugin;

			QLSShim.say("calling panel init");
			try {
				_panel["init"](_host, _w, _h, bridge);
				QLSShim.say("panel init returned");
			} catch(eInit:Error) {
				QLSShim.say("panel init threw: " + eInit.message);
			}
		}

		private static function onLoadError(event:IOErrorEvent):void
		{
			QLSShim.say("IO error loading " + SWF_PATH + " - " + event.text);
		}

		private static function position():void
		{
			if (_panel == null) {
				return;
			}
			try {
				var disp:DisplayObject = DisplayObject(_panel);
				disp.x = _x;
				disp.y = _y;
				_panel["setSize"](_w, _h);
			} catch(e:Error) {
				QLSShim.say("position threw: " + e.message);
			}
		}

		// --- engine bridge ----------------------------------------------------
		//
		// Read out of QuestsTab's bytecode. The two calls are NOT symmetrical:
		//   BGSExternalInterface.call(codeObj, "SetQuestActive", <entry object>)
		//   BGSExternalInterface.call(codeObj, "ShowQuestOnMap", <entry.formID>)

		public static function setQuestActive(formID:Number):Boolean
		{
			var entry:Object = QLSShim.findEntry(formID);
			if (entry == null || _tab == null) {
				QLSShim.say("setQuestActive: no entry for " + formID);
				return false;
			}
			try {
				BGSExternalInterface.call(_tab["codeObj"], "SetQuestActive", entry);
				var sound:String = "UIPipBoyQuestActive";
				if (entry["active"]) {
					sound = "UIPipBoyQuestInactive";
				}
				BGSExternalInterface.call(_tab["codeObj"], "PlaySound", sound);
			}
			catch(e:Error) {
				QLSShim.say("setQuestActive threw: " + e.message);
				return false;
			}
			return true;
		}

		public static function showQuestOnMap(formID:Number):Boolean
		{
			if (_tab == null) {
				return false;
			}
			try {
				BGSExternalInterface.call(_tab["codeObj"], "ShowQuestOnMap", formID);
			}
			catch(e:Error) {
				QLSShim.say("showQuestOnMap threw: " + e.message);
				return false;
			}
			return true;
		}

		private static function findEntry(formID:Number):Object
		{
			var found:Object = QLSShim.searchList(_tab["QuestsList_mc"], formID);
			if (found == null) {
				found = QLSShim.searchList(_tab["ObjectivesList_mc"], formID);
			}
			return found;
		}

		private static function searchList(list:Object, formID:Number):Object
		{
			if (list == null) {
				return null;
			}
			var entries:Array = null;
			try {
				entries = list["entryList"] as Array;
			} catch(e:Error) {
				return null;
			}
			if (entries == null) {
				return null;
			}
			var i:int = 0;
			while (i < entries.length) {
				var entry:Object = entries[i];
				if (entry != null && Number(entry["formID"]) == formID) {
					return entry;
				}
				i = i + 1;
			}
			return null;
		}
	}
}
