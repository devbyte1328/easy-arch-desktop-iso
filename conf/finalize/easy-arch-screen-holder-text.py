import sys
import os
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6.QtGui import QPixmap, QPainter
from PyQt6.QtCore import Qt, QRect, QTimer

# Suppress Qt logging warnings
os.environ["QT_LOGGING_RULES"] = "qt5.widgets.warning=false;qt6.widgets.warning=false"

TRIGGER_FILE = "/tmp/easy-arch-screen-holder-text"

class FullscreenOverlay(QWidget):
    def __init__(self, image_path, screen_geometry):
        super().__init__()
        # Validate image file
        if not os.path.exists(image_path):
            print(f"Error: Image file '{image_path}' not found.", file=sys.stderr)
            QApplication.quit()
        self.pixmap = QPixmap(image_path)
        if self.pixmap.isNull():
            print(f"Error: Failed to load image '{image_path}'.", file=sys.stderr)
            QApplication.quit()

        self.screen_geometry = screen_geometry
        self.setGeometry(self.screen_geometry)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.BypassWindowManagerHint |
            Qt.WindowType.WindowTransparentForInput
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_Source)
        painter.setOpacity(1.0)

        # Scale image to fill the screen (preserve aspect ratio, crop if needed)
        scaled_pixmap = self.pixmap.scaled(
            self.size(),
            Qt.AspectRatioMode.KeepAspectRatioByExpanding,
            Qt.TransformationMode.SmoothTransformation
        )

        # Center the scaled image
        x = (self.width() - scaled_pixmap.width()) // 2
        y = (self.height() - scaled_pixmap.height()) // 2
        painter.drawPixmap(x, y, scaled_pixmap)

def check_trigger_file():
    if not os.path.exists(TRIGGER_FILE):
        QApplication.quit()

if __name__ == "__main__":
    # Create trigger file at startup
    try:
        with open(TRIGGER_FILE, "w") as f:
            f.write("active\n")
    except Exception as e:
        print(f"Error: Could not create trigger file: {e}", file=sys.stderr)
        sys.exit(1)

    app = QApplication(sys.argv)
    overlays = []
    for screen in app.screens():
        geometry = screen.geometry()
        overlay = FullscreenOverlay("easy-arch-screen-holder-text.png", geometry)
        overlay.showFullScreen()
        overlays.append(overlay)

    # Check for file every second
    file_check_timer = QTimer()
    file_check_timer.timeout.connect(check_trigger_file)
    file_check_timer.start(1000)

    sys.exit(app.exec())

