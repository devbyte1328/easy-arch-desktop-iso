import sys
import os
import select
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6.QtGui import QPixmap, QPainter
from PyQt6.QtCore import Qt, QRect, QTimer

# Suppress Qt logging warnings
os.environ["QT_LOGGING_RULES"] = "qt5.widgets.warning=false;qt6.widgets.warning=false"

class FullscreenOverlay(QWidget):
    def __init__(self, image_path, screen_geometry, pipe_fd):
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
        self.pipe_fd = pipe_fd
        self.setGeometry(self.screen_geometry)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.BypassWindowManagerHint
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        # Fallback timeout: 10 seconds
        QTimer.singleShot(10000, self.close_application)
        # Monitor pipe for close signal
        self.setup_pipe_monitor()

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

    def setup_pipe_monitor(self):
        """Monitor pipe for close signal."""
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.check_pipe)
        self.timer.start(100)  # Check every 100ms

    def check_pipe(self):
        """Check if pipe has close signal."""
        r, _, _ = select.select([self.pipe_fd], [], [], 0)
        if r:
            data = os.read(self.pipe_fd, 1024).decode()
            if data == "close":
                self.close_application()

    def close_application(self):
        QApplication.quit()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    # Create pipe for communication
    pipe_r, pipe_w = os.pipe()
    overlays = []
    for screen in app.screens():
        geometry = screen.geometry()
        overlay = FullscreenOverlay("easy-arch-screen-holder.png", geometry, pipe_r)
        overlay.showFullScreen()
        overlays.append(overlay)
    # Store pipe write end in global for shell script
    with open("/tmp/overlay_pipe_fd", "w") as f:
        f.write(str(pipe_w))
    sys.exit(app.exec())
