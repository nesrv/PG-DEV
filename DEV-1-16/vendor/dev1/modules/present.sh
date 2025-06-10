PATH_COURSE=$(realpath "$(pwd)/..")
PATH_MODULES=$(realpath "$PATH_COURSE/modules")
pkill -f SCREEN
firefox --kiosk --new-window $PATH_COURSE/presentation/$1.html 2>/dev/null &
screen -dmS pres $PATH_COURSE/demo/$1.sh
~/gotty --index $PATH_MODULES/gotty.index.html screen -x pres
