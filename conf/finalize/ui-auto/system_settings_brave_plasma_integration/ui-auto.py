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
click('ui-auto/system_settings_brave_plasma_integration/1_KDE_Menu.png')
click('ui-auto/system_settings_brave_plasma_integration/2_App_Search.png')
write("Brave")
click('ui-auto/system_settings_brave_plasma_integration/3_Brave_Browser_App.png')
time.sleep(20)
click('ui-auto/system_settings_brave_plasma_integration/4_Brave_Plasma_Integration_Icon.png', mouse_button='right')
click('ui-auto/system_settings_brave_plasma_integration/5_Brave_Plasma_Integration_Do_Not_Show_Button.png')
click('ui-auto/system_settings_brave_plasma_integration/6_Brave_Browser_Task.png')
click('ui-auto/system_settings_brave_plasma_integration/7_Brave_Browser_Close_Button.png')

