# return 0 if the process name given by the first argument is running, 1 otherwise
ps axo pid,command | grep "\W./$1" | awk '{print $1}' | grep -q .
