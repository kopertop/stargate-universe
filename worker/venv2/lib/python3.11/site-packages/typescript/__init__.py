import os

def checkNode():
    output = os.popen('sh -c "type node"').read()
    return output;