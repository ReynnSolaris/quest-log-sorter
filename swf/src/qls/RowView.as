package qls
{
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	/**
	 * One row in the list. Rows are pooled and re-bound as the list scrolls, so
	 * a 400-quest log costs the same as a 10-quest one.
	 */
	public class RowView extends Sprite
	{
		public static const KIND_SECTION:int = 0;
		public static const KIND_LINE:int = 1;
		public static const KIND_QUEST:int = 2;
		public static const KIND_OBJECTIVE:int = 3;

		public var data:Object;

		private var _background:Shape;
		private var _chevron:Shape;
		private var _bullet:Shape;
		private var _label:TextField;
		private var _meta:TextField;
		private var _width:Number = 400;
		private var _hovered:Boolean = false;

		public function RowView()
		{
			mouseChildren = false;
			buttonMode = true;

			_background = new Shape();
			addChild(_background);

			_chevron = new Shape();
			addChild(_chevron);

			_bullet = new Shape();
			addChild(_bullet);

			_label = makeField();
			addChild(_label);

			_meta = makeField();
			_meta.autoSize = TextFieldAutoSize.RIGHT;
			addChild(_meta);
		}

		private function makeField():TextField
		{
			var field:TextField = new TextField();
			field.selectable = false;
			field.mouseEnabled = false;
			field.multiline = false;
			field.embedFonts = Style.EMBED_FONTS;
			return field;
		}

		public function set hovered(value:Boolean):void
		{
			if (_hovered == value) {
				return;
			}
			_hovered = value;
			drawBackground();
		}

		public function get hovered():Boolean
		{
			return _hovered;
		}

		public function bind(row:Object, width:Number):void
		{
			data = row;
			_width = width;

			var kind:int = int(row.kind);
			var depth:int = int(row.depth);
			var height:Number = kind == KIND_OBJECTIVE ? Style.OBJECTIVE_HEIGHT : Style.ROW_HEIGHT;
			var x:Number = Style.PAD_X + depth * Style.INDENT;

			drawBackground(height);
			drawChevron(row, x, height);
			drawBullet(row, x, height);

			var textX:Number = x + (kind == KIND_OBJECTIVE ? 14 : 16);
			_label.x = textX;
			_label.width = width - textX - 60;
			_label.height = height;
			_label.y = (height - 18) * 0.5;
			_label.text = String(row.label);
			_label.setTextFormat(formatFor(row));

			_meta.x = width - Style.PAD_X - Style.SCROLLBAR_WIDTH;
			_meta.y = _label.y;
			_meta.text = row.meta == null ? "" : String(row.meta);
			_meta.visible = _meta.text.length > 0;
			if (_meta.visible) {
				_meta.setTextFormat(Style.body(11, Style.FG_FAINT));
			}
		}

		private function formatFor(row:Object):TextFormat
		{
			switch (int(row.kind)) {
				case KIND_SECTION:
					return Style.header();
				case KIND_LINE:
					return Style.line();
				case KIND_QUEST:
					if (row.tracked) {
						var tracked:TextFormat = Style.body(13, Style.FG);
						tracked.bold = true;
						return tracked;
					}
					return Style.body(13, row.finished ? Style.FG_FAINT : Style.FG);
				default:
					return Style.objective(12, row.finished ? Style.FG_FAINT : Style.FG_DIM);
			}
		}

		private function drawBackground(height:Number = -1):void
		{
			if (height < 0) {
				height = data != null && int(data.kind) == KIND_OBJECTIVE ?
					Style.OBJECTIVE_HEIGHT : Style.ROW_HEIGHT;
			}

			_background.graphics.clear();

			var alpha:Number = 0;
			if (data != null && data.tracked) {
				alpha = Style.ROW_SELECTED_ALPHA;
			}
			if (_hovered) {
				alpha = Math.max(alpha, Style.ROW_HOVER_ALPHA);
			}

			if (alpha > 0) {
				_background.graphics.beginFill(Style.ROW_HOVER, alpha);
				_background.graphics.drawRect(0, 0, _width, height);
				_background.graphics.endFill();
			}

			// Section rows get a hairline underneath so the tree reads as blocks.
			if (data != null && int(data.kind) == KIND_SECTION) {
				_background.graphics.beginFill(Style.FG, Style.RULE_ALPHA);
				_background.graphics.drawRect(0, height - 1, _width, 1);
				_background.graphics.endFill();
			}

			// Keep the whole row clickable even where nothing is drawn.
			_background.graphics.beginFill(0, 0);
			_background.graphics.drawRect(0, 0, _width, height);
			_background.graphics.endFill();
		}

		private function drawChevron(row:Object, x:Number, height:Number):void
		{
			_chevron.graphics.clear();
			if (!row.expandable) {
				_chevron.visible = false;
				return;
			}
			_chevron.visible = true;

			var size:Number = 5;
			var cy:Number = height * 0.5;
			_chevron.graphics.beginFill(Style.FG, 0.85);
			if (row.collapsed) {
				// pointing right
				_chevron.graphics.moveTo(x, cy - size);
				_chevron.graphics.lineTo(x + size * 1.4, cy);
				_chevron.graphics.lineTo(x, cy + size);
			} else {
				// pointing down
				_chevron.graphics.moveTo(x - size * 0.2, cy - size * 0.6);
				_chevron.graphics.lineTo(x + size * 1.8, cy - size * 0.6);
				_chevron.graphics.lineTo(x + size * 0.8, cy + size * 0.8);
			}
			_chevron.graphics.endFill();
		}

		private function drawBullet(row:Object, x:Number, height:Number):void
		{
			_bullet.graphics.clear();
			if (int(row.kind) != KIND_OBJECTIVE) {
				_bullet.visible = false;
				return;
			}
			_bullet.visible = true;

			var cy:Number = height * 0.5;
			if (row.failed) {
				// cross
				_bullet.graphics.lineStyle(1.5, Style.FG, 0.7);
				_bullet.graphics.moveTo(x, cy - 3);
				_bullet.graphics.lineTo(x + 6, cy + 3);
				_bullet.graphics.moveTo(x + 6, cy - 3);
				_bullet.graphics.lineTo(x, cy + 3);
			} else if (row.finished) {
				// tick
				_bullet.graphics.lineStyle(1.5, Style.FG, 0.55);
				_bullet.graphics.moveTo(x, cy);
				_bullet.graphics.lineTo(x + 2.5, cy + 3);
				_bullet.graphics.lineTo(x + 7, cy - 4);
			} else {
				_bullet.graphics.beginFill(Style.FG, 0.8);
				_bullet.graphics.drawRect(x + 1, cy - 2, 4, 4);
				_bullet.graphics.endFill();
			}
		}
	}
}
