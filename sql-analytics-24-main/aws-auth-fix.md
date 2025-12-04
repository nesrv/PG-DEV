# Исправление ошибки авторизации AWS Builder ID

## Проблема
```
Error: self signed certificate in certificate chain [SELF_SIGNED_CERT_IN_CHAIN]
Failed to connect to AWS Builder ID [FailedToConnect]
```

## Решения

### 1. Отключите проверку SSL в VS Code
```json
// settings.json
{
    "http.proxyStrictSSL": false,
    "aws.telemetry": false
}
```

### 2. Настройте переменные окружения
```bash
export NODE_TLS_REJECT_UNAUTHORIZED=0
export AWS_CA_BUNDLE=""
```

### 3. Используйте корпоративные сертификаты
```bash
# Добавьте корпоративный сертификат
export AWS_CA_BUNDLE=/path/to/corporate-cert.pem
```

### 4. Альтернативная авторизация через AWS CLI
```bash
aws configure sso
aws sso login
```

### 5. Перезапуск
Перезапустите VS Code после изменений

## Альтернативный способ
Авторизация через браузер напрямую на aws.amazon.com/builder-id