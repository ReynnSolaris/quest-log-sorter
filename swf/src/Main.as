package
{
	import flash.display.Sprite;
	import flash.events.Event;

	import qls.QuestLogPanel;

	/**
	 * Document class for QLS.swf.
	 *
	 * This SWF is loaded as a child of PipboyMenu.swf's quest page, so it never
	 * owns the stage. The shim calls init() with the host root and the space it
	 * has been given.
	 */
	[SWF(width = "480", height = "520", frameRate = "30", backgroundColor = "#000000")]
	public class Main extends Sprite
	{
		private var _panel:QuestLogPanel;
		private var _pendingHost:Object;
		private var _pendingBridge:Object;
		private var _pendingWidth:Number = 480;
		private var _pendingHeight:Number = 520;
		private var _ready:Boolean = false;

		public function Main()
		{
			// Deliberately NOT touching stage.align / stage.scaleMode. This SWF
			// is loaded as a child of the Pip-Boy, so the stage belongs to the
			// host menu - reconfiguring it from here would reshape the whole
			// Pip-Boy, and in Scaleform that is not a recoverable mistake.
			_panel = new QuestLogPanel();
			addChild(_panel);

			addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		}

		private function onAddedToStage(event:Event):void
		{
			removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
			_ready = true;
			if (_pendingHost != null) {
				_panel.init(_pendingHost, _pendingWidth, _pendingHeight, _pendingBridge);
			}
		}

		/** Entry point for the PipboyMenu shim. Safe to call before we are on stage. */
		public function init(hostRoot:Object, w:Number, h:Number, bridge:Object = null):void
		{
			_pendingHost = hostRoot;
			_pendingBridge = bridge;
			_pendingWidth = w;
			_pendingHeight = h;
			if (_ready) {
				_panel.init(hostRoot, w, h, bridge);
			}
		}

		/** Call when the Pip-Boy reopens or the quest page regains focus. */
		public function refresh():void
		{
			_panel.refresh();
		}

		public function setSize(w:Number, h:Number):void
		{
			_pendingWidth = w;
			_pendingHeight = h;
			_panel.setSize(w, h);
		}
	}
}
