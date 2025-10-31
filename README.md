# Smart HelpDesk Infrastructure

🚀 Полная инфраструктура для системы HelpDesk "из коробки" с поддержкой Docker Compose и Kubernetes!

## 📋 Сервисы

- **PostgreSQL** - основная реляционная БД
- **MongoDB** - для документ-ориентированных данных  
- **Redis** - для кэширования и сессий
- **MinIO** - S3-совместимое хранилище
- **Keycloak** - аутентификация и авторизация

## 🚀 Быстрый старт 

### Предварительные требования

- **Docker** и **Docker Compose** - для Docker режима
- **Minikube** и **kubectl** - для Kubernetes режима 

### Установка

1. **Клонируйте репозиторий:**
-   ```bash
-  git clone https://github.com/sensssei/hackaton-infra.git
-  cd hackaton-infra
-  ./setup.sh
-  
 # Скрипт автоматически определит доступное окружение:
 - Если обнаружен Kubernetes - предложит выбор режима
 - Если Kubernetes нет - использует Docker Compose
  
### 🐳 Docker Compose режим 

## Доступ к сервисам

- PostgreSQL: localhost:5432
- MongoDB: localhost:27017
- Redis: localhost:6379
- MinIO:
- API: localhost:9000
- Console: localhost:9001 (логин: minioadmin / пароль из .env)
- Keycloak: localhost:8080/admin (логин: admin / пароль из .env)
- 
## Управление
# Просмотр статуса
- docker-compose ps
# Просмотр логов
- docker-compose logs -f [service-name]
# Остановка
- docker-compose down
# Остановка с удалением данных
-docker-compose down -v

### ☸️ Kubernetes режим
## Запуск
# Убедитесь что Minikube запущен
- minikube status
# Запустите setup.sh
- ./setup.sh
# Выберите Kubernetes когда скрипт предложит

## Доступ к сервисам

# Получитm IP Minikube
- minikube ip
# Или используйте port-forward для доступа:
- kubectl port-forward -n helpdesk-infra service/postgres 5432:5432 &
- kubectl port-forward -n helpdesk-infra service/mongodb 27017:27017 &
- kubectl port-forward -n helpdesk-infra service/redis 6379:6379 &
- kubectl port-forward -n helpdesk-infra service/minio 9000:9000 9001:9001 &
- kubectl port-forward -n helpdesk-infra service/keycloak 8080:8080 &

## Управление
# Просмотр всех ресурсов
- kubectl get all -n helpdesk-infra

# Просмотр подов
- kubectl get pods -n helpdesk-infra -w

# Просмотр логов
- kubectl logs -n helpdesk-infra [pod-name]

# Удаление namespace (полная очистка)
- kubectl delete namespace helpdesk-infra