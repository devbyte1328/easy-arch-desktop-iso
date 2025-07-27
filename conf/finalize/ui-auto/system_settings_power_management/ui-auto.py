import pyautogui
import time
import subprocess

pyautogui.FAILSAFE = False

def click(path, confidence=0.8, wait_time=1, max_attempts=5, mouse_button='left'):
    disable_text = False
    for attempt in range(max_attempts):
        try:
            time.sleep(wait_time)
            location = pyautogui.locateCenterOnScreen(path, confidence=confidence)
            if location:
                pyautogui.click(location, button=mouse_button)
                if disable_text == True:
                    subprocess.Popen(['bash', '-c', 'sleep 1.5 && source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/easy-arch-screen-holder-text.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['touch', '/home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-3'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.Popen(['bash', '-c', 'sleep 1.5 && source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/easy-arch-screen-holder-loading.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    disable_text = False
                return True
        except Exception as e:
            subprocess.run(['rm', '/home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-text'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(['rm', '/home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-3'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            disable_text = True
            print(f"Exception occurred on attempt {attempt + 1}: {e}")
    raise RuntimeError(f"Failed to find image on screen after {max_attempts} attempts: {path}")

def write(text, wait_time=1):
    pyautogui.write(text)
    time.sleep(wait_time)

pyautogui.hotkey('win', 'd')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/1_KDE_Menu.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/2_App_Search.png')
write("System Settings")
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/3_System_Settings_App.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/4_System_Settings_Background_Unclear_Button.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/5_System_Settings_Search.png')
write("Power Management")
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/6_Power-Management_Settings.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/7_Show_Logout_Screen_Option.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/8_Show_Logout_Screen_Shutdown_Button.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/9_Turn_Off_Screen_Option.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/10_Turn_Off_Screen_Never_Button.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/11_Screen_Locking_Apply.png')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/12_System_Settings_Task.png', mouse_button='right')
click('/home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-path/13_System_Settings_Close.png')

