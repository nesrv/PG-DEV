# Кусок для включения в конец ${course}_setup_vm.sh

# Настраиваем слои OverlayFS
. ${SCRIPT_PATH}/modules/overlays_on.sh

# Сбрасываем к нижнему слою
~/reset.sh
