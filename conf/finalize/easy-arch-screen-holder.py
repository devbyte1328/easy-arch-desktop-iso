import sys
import os
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6.QtGui import QPixmap, QPainter
from PyQt6.QtCore import Qt, QRect, QTimer

# Suppress Qt logging warnings
os.environ["QT_LOGGING_RULES"] = "qt5.widgets.warning=false;qt6.widgets.warning=false"

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
        center_rect = QRect(
            (self.width() - self.pixmap.width()) // 2,
            (self.height() - self.pixmap.height()) // 2,
            self.pixmap.width(),
            self.pixmap.height()
        )
        painter.drawPixmap(center_rect, self.pixmap)

def check_trigger_file():
    trigger_path = "/tmp/easy-arch-screen-holder"
    if os.path.exists(trigger_path):
        os.remove(trigger_path)
        QApplication.quit()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    overlays = []
    for screen in app.screens():
        geometry = screen.geometry()
        overlay = FullscreenOverlay("easy-arch-screen-holder.png", geometry)
        overlay.showFullScreen()
        overlays.append(overlay)

    # Check for file every second
    file_check_timer = QTimer()
    file_check_timer.timeout.connect(check_trigger_file)
    file_check_timer.start(1000)  # every 1000 ms

    sys.exit(app.exec())

