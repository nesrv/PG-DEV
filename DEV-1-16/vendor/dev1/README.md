# DEV1 Базовый курс для разработчиков серверной части приложений

## Клонирование репозитория

Первый раз выполните следующую команду:

```
git clone https://pubgit.postgrespro.ru/edu/dev1.git --recurse-submodules --branch 16
```

Чтобы не вводить каждый раз имя и пароль, можно сгенерировать SSH-ключ (здесь написано, как: https://pubgit.postgrespro.ru/help/user/ssh) и записать открытый ключ в gitlab: https://pubgit.postgrespro.ru/-/user_settings/ssh_keys


После этого репозиторий можно будет клонировать так:

```
git clone git@pubgit.postgrespro.ru:edu/dev1.git --recurse-submodules --branch 16
```

## Обновление репозитория

Чтобы впоследствии обновить материалы курса, выполните:

```
cd dev1
git pull
git submodule update
```

