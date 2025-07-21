import pyautogui
import time
import subprocess

def click(path, confidence=0.8, wait_time=1, max_attempts=5, mouse_button='left'):
    disable_text = False
    for attempt in range(max_attempts):
        try:
            time.sleep(wait_time)
            location = pyautogui.locateCenterOnScreen(path, confidence=confidence)
            if location:
                pyautogui.click(location, button=mouse_button)
                if disable_text == True:
                    subprocess.Popen(['bash', '-c', 'sleep 1.5 && source venv/bin/activate && python easy-arch-screen-holder-text.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    disable_text = False
                return True
        except Exception as e:
            subprocess.run(['rm', '/tmp/easy-arch-screen-holder-text'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            disable_text = True
            print(f"Exception occurred on attempt {attempt + 1}: {e}")
    raise RuntimeError(f"Failed to find image on screen after {max_attempts} attempts: {path}")

def write(text, wait_time=1):
    pyautogui.write(text)
    time.sleep(wait_time)

pyautogui.hotkey('win', 'd')
click('ui-auto/system_settings_clear_clipboard_history/1_KDE_Menu.png')
click('ui-auto/system_settings_clear_clipboard_history/2_App_Search.png')
write("Clipboard_Text")
pyautogui.hotkey('ctrl', 'a')
pyautogui.hotkey('ctrl', 'x')
click('ui-auto/system_settings_clear_clipboard_history/3_Clipboard_List.png')
click('ui-auto/system_settings_clear_clipboard_history/4_Clear_Clipboard_History_Button.png')
click('ui-auto/system_settings_clear_clipboard_history/5_Do_Not_Ask_Again_Check.png')
click('ui-auto/system_settings_clear_clipboard_history/6_Do_Not_Ask_Again_Delete_Button.png')
