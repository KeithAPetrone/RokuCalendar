# RokuCalendar

A dedicated digital wall calendar and photo slideshow app for Roku devices. Designed to be an "always-on" display for your home.

![Version](https://img.shields.io/badge/version-1.0.1-blue)
![Platform](https://img.shields.io/badge/platform-Roku-orange)

## Features

- **Photo Slideshow:** Cycles through images from a specific Dropbox folder with smooth cross-fade transitions.
- **Dynamic Calendar:** Synchronizes with your Google Calendar. Supports monthly grid and weekly timeline views.
- **Auto-Refresh:** Automatically fetches new photos (10 min) and calendar entries (15 min) in the background.
- **Live Weather:** Displays current temperature and conditions for your local area.
- **Always-On Display:** Automatically disables the Roku screensaver while the app is active.
- **Adaptive Layout:** Multi-lane system for overlapping events and automatic text scaling for better readability.

## Setup Instructions

### 1. Configuration File
Before deploying, you must create a configuration file:
1.  Navigate to the `source/` directory.
2.  Copy `config.brs.template` and rename it to `config.brs`.
3.  Open `config.brs` and fill in your details (see below).

### 2. Dropbox Authentication (Photos)
To link your Dropbox account:
1.  Ensure you have a folder in your Dropbox (e.g., `/RokuPhotos`) with some images.
2.  Run the provided PowerShell script on your computer:
    ```powershell
    .\get_dropbox_token.ps1
    ```
3.  Follow the prompts to log in and authorize the app. The script will automatically save your permanent `refreshToken` into your `config.brs`.

### 3. Google Calendar Authentication
1.  Deploy the app to your Roku.
2.  On the first launch, a "Login Required" overlay will appear with a URL and a code.
3.  Visit the URL on your phone or computer, enter the code, and click "Allow."
4.  The app will automatically detect the login and display your calendar.

### 4. Customizing Weather
By default, the app uses GeoIP to find your location. To set a specific location:
1.  Open `source/config.brs`.
2.  Enter your `latitude`, `longitude`, and `city` name in the `weather` section.

## Usage
- **Press OK / Play / Options:** Toggle between **Monthly Grid** and **Weekly Timeline** views.
- **Press Back:** Closes the login overlay if it appears.

## Developer Note
This app is optimized for performance and will not trigger Roku system "busy loops," ensuring your device remains responsive.
