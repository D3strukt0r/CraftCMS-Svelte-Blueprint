# Setup a red prompt for root and a green one for users.
NORMAL="\e[0m"
GREEN="\e[38;5;10m"
RED="\e[1;31m"
BLUE="\e[38;5;12m"

if [ "$USER" = root ]; then
    PS1="🐳 $RED\u@\h$NORMAL:$BLUE\w$NORMAL\\$ "
else
    PS1="🐳 $GREEN\u@\h$NORMAL:$BLUE\w$NORMAL\\$ "
fi
