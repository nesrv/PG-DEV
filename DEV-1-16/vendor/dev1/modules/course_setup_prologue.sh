# Кусок для включения в начало ${course}_setup_vm.sh

cd

# Сбрасываем слои OverlayFS
. ${SCRIPT_PATH}/modules/overlays_off.sh

# Переменные (стираем старые)
sed -i '/^#course variables/,$d' ~/.profile
echo '#course variables' >> ~/.profile
cat "${SCRIPT_PATH}"/{modules/environment,environment} | while read line
do
  echo "export $line" >> ~/.profile
done
set -a
. "${SCRIPT_PATH}"/modules/environment
. "${SCRIPT_PATH}"/environment
set +a

# Обновляем сертификаты
sudo apt update
sudo apt install -y ca-certificates

# Подсветка синтаксиса
sudo cp "${SCRIPT_PATH}"/modules/*.lang /usr/share/highlight/langDefs/
sudo chmod 644 /usr/share/highlight/langDefs/*.lang

# Сносим все кластеры PostgreSQL
echo deleting all postgres clusters ...
  pg_lsclusters -h | grep -Eo '^[0-9]{2} [[:alnum:]]+' | while read cluster ; do
  echo dropping cluster $cluster...
  sudo pg_dropcluster $cluster --stop
done
sudo rm -rf /etc/postgresql
sudo rm -rf /var/lib/postgresql
