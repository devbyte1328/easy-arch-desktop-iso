import sys
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6.QtGui import QPixmap, QPainter
from PyQt6.QtCore import Qt, QRect


class FullscreenOverlay(QWidget):
    def __init__(self, image_path, screen_geometry):
        super().__init__()
        self.pixmap = QPixmap(image_path)
        self.screen_geometry = screen_geometry

        self.setGeometry(self.screen_geometry)

        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)

        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        # Grabs are NOT supported under Wayland unless the window is a popup
        # self.grabKeyboard()
        # self.grabMouse()

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

    def keyPressEvent(self, event):
        QApplication.quit()

    def mousePressEvent(self, event):
        QApplication.quit()

    def mouseMoveEvent(self, event):
        QApplication.quit()

    def wheelEvent(self, event):
        QApplication.quit()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    overlays = []

    for screen in app.screens():
        geometry = screen.geometry()
        overlay = FullscreenOverlay("image.png", geometry)
        overlay.showFullScreen()
        overlays.append(overlay)

    sys.exit(app.exec())

