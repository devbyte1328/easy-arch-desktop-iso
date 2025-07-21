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
                    subprocess.run(['touch', '/tmp/easy-arch-screen-holder-loading-3'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.Popen(['bash', '-c', 'sleep 1.5 && source venv/bin/activate && python easy-arch-screen-holder-loading.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    disable_text = False
                return True
        except Exception as e:
            subprocess.run(['rm', '/tmp/easy-arch-screen-holder-text'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(['rm', '/tmp/easy-arch-screen-holder-loading-3'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            disable_text = True
            print(f"Exception occurred on attempt {attempt + 1}: {e}")
    raise RuntimeError(f"Failed to find image on screen after {max_attempts} attempts: {path}")

def write(text, wait_time=1):
    pyautogui.write(text)
    time.sleep(wait_time)

pyautogui.hotkey('win', 'd')
click('ui-auto/system_settings_screen_locking/ui-path/1_KDE_Menu.png')
click('ui-auto/system_settings_screen_locking/ui-path/2_App_Search.png')
write("System Settings")
click('ui-auto/system_settings_screen_locking/ui-path/3_System_Settings_App.png')
click('ui-auto/system_settings_screen_locking/ui-path/4_System_Settings_Background_Unclear_Button.png')
click('ui-auto/system_settings_screen_locking/ui-path/5_System_Settings_Search.png')
write("Screen Locking")
click('ui-auto/system_settings_screen_locking/ui-path/6_Screen_Locking_Settings.png')
click('ui-auto/system_settings_screen_locking/ui-path/7_Screen_Locking_Automatic_Option.png')
click('ui-auto/system_settings_screen_locking/ui-path/8_Screen_Locking_Automatic_Option_Button.png')
click('ui-auto/system_settings_screen_locking/ui-path/9_Screen_Locking_Sleep_Button.png')
click('ui-auto/system_settings_screen_locking/ui-path/10_Screen_Locking_Apply.png')
click('ui-auto/system_settings_screen_locking/ui-path/11_System_Settings_Task.png', mouse_button='right')
click('ui-auto/system_settings_screen_locking/ui-path/12_System_Settings_Close.png')

