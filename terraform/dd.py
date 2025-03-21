import os
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException

def test_test():
    driver = None
    try:
        print("Starting DefectDojo configuration script...")
        
        # Set up Chrome options
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1920,1080")
        # Increase timeouts for slower environments
        chrome_options.add_argument("--browser-timeout=60")
        
        # Install Chrome and ChromeDriver if needed (on Ubuntu)
        if not os.path.exists("/usr/bin/google-chrome"):
            print("Installing Chrome...")
            os.system("sudo apt-get update")
            os.system("sudo apt-get install -y wget unzip")
            os.system("wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb")
            os.system("sudo apt-get install -y ./google-chrome-stable_current_amd64.deb")
        
        if not os.path.exists("/usr/local/bin/chromedriver"):
            print("Installing ChromeDriver...")
            # Determine Chrome version
            chrome_version = os.popen("google-chrome --version").read().strip().split()[2].split('.')[0]
            print(f"Detected Chrome version: {chrome_version}")
            
            # Download appropriate ChromeDriver
            os.system(f"wget -q https://chromedriver.storage.googleapis.com/LATEST_RELEASE_{chrome_version}")
            chromedriver_version = open(f"LATEST_RELEASE_{chrome_version}").read()
            os.system(f"wget -q https://chromedriver.storage.googleapis.com/{chromedriver_version}/chromedriver_linux64.zip")
            os.system("unzip -o chromedriver_linux64.zip")
            os.system("sudo mv chromedriver /usr/local/bin/")
            os.system("sudo chmod +x /usr/local/bin/chromedriver")
        
        # Fetch secrets from environment variables first (if available)
        sonarqubepassword = os.environ.get('SONARQUBE_PASSWORD')
        defectdojoUIPassword = os.environ.get('DEFECTDOJO_PASSWORD')
        defectDojoDomain = os.environ.get('DEFECTDOJO_DOMAIN')
        
        # Fall back to Key Vault if environment variables aren't set
        if not sonarqubepassword:
            print("Fetching SonarQube password from Key Vault...")
            command = "az keyvault secret show --name sonarqubepassword --vault-name Securelinevault1 --query value -o tsv"
            sonarqubepassword = os.popen(command).read().strip()
            if not sonarqubepassword:
                raise Exception("Failed to retrieve SonarQube password")
        
        if not defectdojoUIPassword:
            print("Fetching DefectDojo password from Key Vault...")
            command1 = "az keyvault secret show --name defectdojoUIPassword --vault-name Securelinevault1 --query value -o tsv"
            defectdojoUIPassword = os.popen(command1).read().strip()
            if not defectdojoUIPassword:
                raise Exception("Failed to retrieve DefectDojo password")
        
        # Initialize WebDriver with options
        print("Initializing Chrome WebDriver...")
        driver = webdriver.Chrome(options=chrome_options)
        
        # Create a WebDriverWait instance for explicit waits
        wait = WebDriverWait(driver, 30)  # 30 second timeout
        
        # Define URL with variable for flexibility
        base_url = f"http://{defectDojoDomain}:30001"
        login_url = f"{base_url}/login?next=/"
        
        # Navigate to login page
        print(f"Navigating to DefectDojo login page at {login_url}")
        driver.get(login_url)
        
        # Wait for page to load and check if we're on the right page
        try:
            # Try to find an element that should be on the login page
            wait.until(EC.presence_of_element_located((By.TAG_NAME, "form")))
            print("Login page loaded successfully")
        except TimeoutException:
            print("Current URL:", driver.current_url)
            print("Page source:", driver.page_source[:500])  # Print first 500 chars for debugging
            raise Exception("Login page did not load properly or has unexpected structure")
        
        # Find and interact with login form elements with explicit waits
        print("Attempting to log in...")
        username_field = wait.until(EC.presence_of_element_located((By.ID, "id_username")))
        username_field.clear()
        username_field.send_keys("admin")
        
        password_field = wait.until(EC.presence_of_element_located((By.ID, "id_password")))
        password_field.clear()
        password_field.send_keys(defectdojoUIPassword)
        
        # Click login button
        login_button = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, ".btn-success")))
        login_button.click()
        
        # Wait for login to complete and dashboard to load
        wait.until(EC.url_contains("/dashboard"))
        print("Successfully logged in")
        
        # Navigate to tool config page
        print("Navigating to tool configuration page")
        driver.get(f"{base_url}/tool_config")
        
        # Wait for page to load
        time.sleep(2)  # Small sleep to ensure page is fully loaded
        
        # Click on SonarQube tool configuration
        print("Opening SonarQube configuration")
        tool_link = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "b")))
        tool_link.click()
        
        # Wait for the edit form to appear
        wait.until(EC.presence_of_element_located((By.ID, "id_password")))
        
        # Update SonarQube password
        print("Updating SonarQube password")
        password_input = driver.find_element(By.ID, "id_password")
        password_input.clear()
        password_input.send_keys(sonarqubepassword)
        
        # Save the changes
        save_button = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, ".col-sm-offset-2 > .btn")))
        save_button.click()
        
        # Wait for save to complete
        time.sleep(2)
        
        # Log out
        print("Logging out")
        user_dropdown = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, ".dropdown:nth-child(3) > .dropdown-toggle")))
        user_dropdown.click()
        
        logout_link = wait.until(EC.element_to_be_clickable((By.LINK_TEXT, "Logout")))
        logout_link.click()
        
        print("DefectDojo configuration completed successfully")
        
    except Exception as e:
        print(f"Something went wrong: {str(e)}")
        
        # Print additional debugging information if we have a driver instance
        if driver:
            try:
                print(f"Current URL: {driver.current_url}")
                print(f"Page title: {driver.title}")
                # Take a screenshot for debugging
                screenshot_path = "/tmp/defectdojo_error.png"
                driver.save_screenshot(screenshot_path)
                print(f"Screenshot saved to {screenshot_path}")
            except:
                print("Could not get additional debugging info")
    finally:
        # Clean up
        if driver:
            try:
                driver.quit()
                print("Browser session closed")
            except:
                print("Error closing browser session")

if __name__ == "__main__":
    test_test()