# Временно отключает OverlayFS, чтобы сделать изменения в нижнем слое.

# Останавливаем все кластеры
echo stopping all postgres clusters ...
pg_lsclusters -h | grep -Eo '^[0-9]{2} [[:alnum:]]+' | while read cluster ; do
  sudo pg_ctlcluster $cluster stop
done

# Добиваем остальные процессы
sudo killall -QUIT postgres >& /dev/null

# Отмонтируем OverlayFS
echo setting up overlayfs mountpoints ...
for target in $OVERLAY_DIRS
do
	mountpoint -q "$target" && sudo umount "$target"
	target_escaped=${target//\//\\\/}
	basename=/var/lib/.reset/${target//\//_}
	sudo sed -i /${target_escaped}/d /etc/fstab
	sudo systemctl daemon-reload
	if [ -d "$basename" ]
	then
		sudo rm -rf $target
		sudo mv $basename/lower $target
		sudo rm -rf $basename
	fi
done

#echo mounts:
#sudo mount | grep overlay
#read -p ..1

# Чистим ~student/tmp
echo "cleaning up ~student/tmp ..."
sudo rm -rf ~student/tmp
