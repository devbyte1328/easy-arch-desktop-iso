import pyautogui
import time

# Give some time to switch to the target screen
time.sleep(2)

# Locate the image on the screen
location = pyautogui.locateCenterOnScreen('image.png', confidence=0.8)  # Adjust confidence as needed

if location is not None:
    print(f"Found image at: {location}")
    pyautogui.click(location)
else:
    print("Image not found.")
