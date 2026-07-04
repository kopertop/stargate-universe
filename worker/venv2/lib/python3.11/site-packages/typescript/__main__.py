import os

def nodeIsInBin():
    nodeString = checkNode()
    if len(nodeString) >= 9:
        return True

def init(directory):
    if(nodeIsInBin()):
        cwd = os.getcwd()
        cwf = os.path.dirname(os.path.abspath(__file__))
        
        if cwd is not None:
            cmd = 'sh -c "node '
            cmd+=cwd 
            cmd+="/dist/parser.tp -d "
            cmd+=cwd
            cmd+='"'
            output = os.popen(cmd).read()
        elif cwf is not None:
            cmd = 'sh -c "node '
            cmd+=cwf 
            cmd+="/dist/parser.tp -f "
            cmd+=cwf
            cmd+='"'
            output = os.popen(cmd).read()
    else:
        print("Please make sure node.js has been installed and is on your users path!")
