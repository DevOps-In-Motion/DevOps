import requests


def endpointGet(endpoint, auth):

  try:


  except as err:
    print(err)
    
  if auth:
    res = requests.get(endpoint, params=auth)
  else:
    res = requests.get(endpoint)
  return res.json()