@echo off
echo ========================================
echo Unity Ads Plugin Build Script
echo ========================================
echo.

cd /d "%~dp0"

REM JDK 17. AGP 8.1 will not run on 21 or 25, both of which are also installed,
REM so pin it here rather than trusting whatever JAVA_HOME happens to be.
if not defined JAVA_HOME set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo ERROR: JDK 17 not found at %JAVA_HOME%
    pause
    exit /b 1
)

REM Godot's own Android build template is the source of godot-lib.aar — it is
REM installed in the project already, so there is nothing to download.
if not exist "libs\godot-lib.aar" (
    echo Copying godot-lib.aar from the Android build template...
    if not exist "libs" mkdir "libs"
    copy /Y "..\android\build\libs\release\godot-lib.template_release.aar" "libs\godot-lib.aar"
)

if not exist "libs\godot-lib.aar" (
    echo ERROR: godot-lib.aar not found and could not be copied.
    echo Run Project ^> Install Android Build Template in Godot first.
    pause
    exit /b 1
)

REM Points Gradle at the same SDK the Godot editor uses.
if not exist "local.properties" (
    echo sdk.dir=C\:\\Users\\USER\\android_sdk> local.properties
)

echo Found godot-lib.aar
echo.

if not exist "gradlew.bat" (
    echo Generating Gradle wrapper...
    call gradle wrapper --gradle-version 8.4
)

echo Building plugin (debug + release)...
call gradlew.bat assembleDebug assembleRelease

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED!
    pause
    exit /b 1
)

echo.
echo Copying AARs into addons\GodotUnityAds\bin ...

if not exist "..\addons\GodotUnityAds\bin\debug"   mkdir "..\addons\GodotUnityAds\bin\debug"
if not exist "..\addons\GodotUnityAds\bin\release" mkdir "..\addons\GodotUnityAds\bin\release"

copy /Y "build\outputs\aar\GodotUnityAds-debug.aar"   "..\addons\GodotUnityAds\bin\debug\GodotUnityAds-debug.aar"
copy /Y "build\outputs\aar\GodotUnityAds-release.aar" "..\addons\GodotUnityAds\bin\release\GodotUnityAds-release.aar"

echo.
echo ========================================
echo BUILD SUCCESSFUL!
echo ========================================
echo.
pause
