package qls
{
	import flash.text.TextFormat;

	/**
	 * Visual constants. The Pip-Boy tints everything with a single player-chosen
	 * colour, so we draw in greyscale/alpha and let the host's colour transform
	 * do the tinting. That is also why this matches FallUI presets for free:
	 * FallUI does not repaint the Pip-Boy, the game does.
	 */
	public class Style
	{
		// --- metrics ---
		public static const ROW_HEIGHT:Number = 24;
		public static const OBJECTIVE_HEIGHT:Number = 20;
		public static const INDENT:Number = 16;
		public static const PAD_X:Number = 8;
		public static const SEARCH_HEIGHT:Number = 26;
		public static const SCROLLBAR_WIDTH:Number = 4;

		// --- colours (pre-tint) ---
		public static const FG:uint = 0xFFFFFF;
		public static const FG_DIM:uint = 0x9A9A9A;
		public static const FG_FAINT:uint = 0x5E5E5E;
		public static const ROW_HOVER:uint = 0xFFFFFF;
		public static const ROW_HOVER_ALPHA:Number = 0.12;
		public static const ROW_SELECTED_ALPHA:Number = 0.22;
		public static const RULE_ALPHA:Number = 0.18;

		/**
		 * Set this to a font the host movie actually embeds, otherwise every
		 * TextField falls back to a device font and looks wrong. Open
		 * PipboyMenu.swf in JPEXS, look under "fonts", and copy the exact name
		 * (Fallout 4 font names start with "$").
		 */
		public static var FONT:String = "$MonoFont";

		/**
		 * false = use the host movie's font by name (recommended: PipboyMenu.swf
		 * already ships the right glyphs and the right localisation, and your
		 * panel picks up any font replacer the player installed).
		 * true  = only if you embed a TTF into QLS.swf yourself, in which case
		 * set FONT to the fontName you gave the [Embed] tag.
		 */
		public static var EMBED_FONTS:Boolean = false;

		public static function header(size:Number = 15):TextFormat
		{
			var format:TextFormat = new TextFormat(FONT, size, FG);
			format.letterSpacing = 1.5;
			format.bold = true;
			return format;
		}

		public static function line(size:Number = 14):TextFormat
		{
			var format:TextFormat = new TextFormat(FONT, size, FG);
			format.letterSpacing = 0.8;
			return format;
		}

		public static function body(size:Number = 13, colour:uint = FG):TextFormat
		{
			return new TextFormat(FONT, size, colour);
		}

		public static function objective(size:Number = 12, colour:uint = FG_DIM):TextFormat
		{
			return new TextFormat(FONT, size, colour);
		}
	}
}
