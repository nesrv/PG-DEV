# Восстанавливает точки монтирования OverlayFS

# Останавливаем все кластеры
echo stopping all postgres clusters ...
pg_lsclusters -h | grep -Eo '^[0-9]{2} [[:alnum:]]+' | while read cluster ; do
  sudo pg_ctlcluster $cluster stop
done

# Остальное добиваем
sudo killall -QUIT postgres >& /dev/null

sudo rm -rf /var/lib/.reset
# delete non-root mounts
sudo sed -i -E '/^mount.*\/[^ ]+$/d' /sbin/mount-overlay.sh
for target in $OVERLAY_DIRS
do
	target_escaped=${target//\//\\\/}
	basename=/var/lib/.reset/${target//\//_}
	sudo mkdir -p $basename/{work,upper}
	sudo chown -R postgres: $basename/{work,upper}
	sudo mv $target $basename/lower
	sudo mkdir $target
	sudo chown postgres: $target
	sudo sed -i /${target_escaped}/d /etc/fstab
	sudo tee -a /etc/fstab > /dev/null <<- EOT
		overlay $target overlay lowerdir=$basename/lower,upperdir=$basename/upper,workdir=$basename/work 0 0
	EOT
	sudo systemctl daemon-reload
	# insert after root mount
	sudo sed -i "/^mount.* \/$/a mount ${target_escaped}" /sbin/mount-overlay.sh
	sudo mount $target
done
