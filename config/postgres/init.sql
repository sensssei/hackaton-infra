-- Создаем базы данных если они не существуют
CREATE DATABASE IF NOT EXISTS keycloak;
CREATE DATABASE IF NOT EXISTS helpdesk;

-- Даем полные права пользователю на обе базы
GRANT ALL PRIVILEGES ON DATABASE keycloak TO helpdesk_user;
GRANT ALL PRIVILEGES ON DATABASE helpdesk TO helpdesk_user;
