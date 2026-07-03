# This is a simple script to resolve the geo location of a list of IP addresses
# using the publicly available geolocation-db.com API endpoint

import requests
import json
import time
import pandas as pd
import os

path = '/local/user/storage/' 					# set local path
data_file = 'ip_address_list.csv' 				# IP source file
output_file = 'Sip_address_list_resolved.csv'	# Resolved Geo Location for IP address
output = path + output_file
url = "https://geolocation-db.com/json/"		# database with IP range geos
clicks = pd.read_csv(os.path.join(path, data_file))
data_df = pd.DataFrame()

for index, row in clicks.iterrows():
    context_ip = row['context_ip']
    ip_address = str(context_ip)
    response = requests.get(url + ip_address)
    str_response = str(response)
    try :
        data = response.json()
        print(data)
        new_data = pd.DataFrame(data, index=[0])
        data_df = data_df.append(new_data, ignore_index=True)
    except Exception:
        print('Error on: ', ip_address)
        with open('ip_script_errors.txt', 'a') as myfile:
            myfile.write('Error on: ' + ip_address + ' - ')
            myfile.write(str_response + ' ' + ip_address + '\n')
        continue
    time.sleep(0.001)

data_df.to_csv(output)
