import sys
import os
import re
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6.QtGui import QPixmap, QPainter
from PyQt6.QtCore import Qt, QTimer
from Xlib import display, X

# Suppress Qt logging warnings
os.environ["QT_LOGGING_RULES"] = "qt5.widgets.warning=false;qt6.widgets.warning=false"

TRIGGER_DIR = "/tmp"
TRIGGER_PREFIX = "easy-arch-screen-holder-loading-"
TRIGGER_PATTERN = re.compile(rf"^{TRIGGER_PREFIX}(\d+)$")

class FullscreenOverlay(QWidget):
    def __init__(self, image_path, screen_geometry):
        super().__init__()
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

        self.showFullScreen()
        QTimer.singleShot(200, self.raise_x11_window)

    def raise_x11_window(self):
        try:
            win_id = int(self.winId())
            d = display.Display()
            w = d.create_resource_object('window', win_id)
            w.configure(stack_mode=X.Above)
            d.sync()
        except Exception as e:
            print(f"Warning: Failed to raise window: {e}", file=sys.stderr)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_Source)
        painter.setOpacity(1.0)

        scaled_pixmap = self.pixmap.scaled(
            self.size(),
            Qt.AspectRatioMode.KeepAspectRatioByExpanding,
            Qt.TransformationMode.SmoothTransformation
        )
        x = (self.width() - scaled_pixmap.width()) // 2
        y = (self.height() - scaled_pixmap.height()) // 2
        painter.drawPixmap(x, y, scaled_pixmap)

def find_trigger_file():
    for name in os.listdir(TRIGGER_DIR):
        match = TRIGGER_PATTERN.match(name)
        if match:
            return int(match.group(1))
    return None

class OverlayManager:
    def __init__(self, app):
        self.app = app
        self.overlays = []
        self.current_number = None

    def update_overlays(self):
        number = find_trigger_file()
        if number is None:
            self.cleanup_and_exit()
            return

        if number != self.current_number:
            self.current_number = number
            self.reload_overlays(number)

    def reload_overlays(self, number):
        for overlay in self.overlays:
            overlay.close()
        self.overlays.clear()

        image_path = f"easy-arch-screen-holder-loading-{number}.png"
        for screen in self.app.screens():
            geometry = screen.geometry()
            overlay = FullscreenOverlay(image_path, geometry)
            self.overlays.append(overlay)

    def cleanup_and_exit(self):
        for overlay in self.overlays:
            overlay.close()
        self.app.quit()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    manager = OverlayManager(app)

    # Initial check
    if find_trigger_file() is None:
        print("No trigger file found. Exiting.")
        sys.exit(0)

    manager.update_overlays()

    # Check for updates every 500ms
    timer = QTimer()
    timer.timeout.connect(manager.update_overlays)
    timer.start(500)

    sys.exit(app.exec())

