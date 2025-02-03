import time
import os
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options


def test_test():
    try:
        # Set up Chrome options
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")

        # Initialize WebDriver with options
        driver = webdriver.Chrome(options=chrome_options)
        #driver = webdriver.Chrome()
        command = "az keyvault secret show --name sonarqubepassword --vault-name  Securelinevault1 --query value -o tsv"
        sonarqubepassword = os.popen(command).read().strip()
        command1 = "az keyvault secret show --name defectdojoUIPassword --vault-name Securelinevault1 --query value -o tsv"
        defectdojoUIPassword = os.popen(command1).read().strip()
        driver.get("http://securelinearecord.demodomain.co:30001/login?next=/")
        driver.set_window_size(1552, 832)
        driver.find_element(By.ID, "id_username").send_keys("admin")
        driver.find_element(By.ID, "id_password").send_keys(defectdojoUIPassword)
        driver.find_element(By.CSS_SELECTOR, ".btn-success").click()
        driver.get("http://securelinearecord.demodomain.co:30001/tool_config")
        driver.find_element(By.CSS_SELECTOR, "b").click()
        driver.find_element(By.ID, "id_password").click()
        driver.find_element(By.ID, "id_password").clear()
        driver.find_element(By.ID, "id_password").send_keys(sonarqubepassword)
        driver.find_element(By.CSS_SELECTOR, ".col-sm-offset-2 > .btn").click()
        driver.find_element(By.CSS_SELECTOR, ".dropdown:nth-child(3) > .dropdown-toggle").click()
        driver.find_element(By.LINK_TEXT, "Logout").click()
        driver.quit()
    except Exception as e:
        print("Something went wrong Error : "+str(e))
test_test()