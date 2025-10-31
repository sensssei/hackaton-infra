#!/bin/bash

set -e

echo "🚀 Starting Smart HelpDesk Infrastructure Setup..."
echo "================================================"

# Функция для детекта режима развертывания
detect_deployment_mode() {
    # Проверяем доступность kubectl и наличие кластера
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>/dev/null; then
        echo "🎯 Kubernetes cluster detected"
        return 0
    else
        echo "🐳 Using Docker Compose mode"
        return 1
    fi
}

# Проверяем установлен ли Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Докер не установлен. Для начала установите Docker."
    exit 1
fi

# Проверяем установлен ли Docker Compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose Не установлен. Пожалуйста проверьте установлен ли Docker Compose."
    exit 1
fi

# Создаем .env файл, если такого нету
if [ ! -f .env ]; then
    echo "📝 Создаем .env файл из .env.example..."
    cp .env.example .env
    echo "⚠️  Пожалуйста отредактируйте .env файл на ваши актуальные пароли!"
fi

# Генерируем рандомные пароли если .env пустой 
if [ ! -s .env ] || grep -q "strong_password_here" .env; then
    echo "🔐 Генерируем пароли..."
    
    # Генерируем рандомный пароль
    POSTGRES_PASSWORD=$(openssl rand -hex 32 2>/dev/null || echo "postgres_secure_123")
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "mongo_secure_123") 
    REDIS_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "redis_secure_123")
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "minio_secure_123")
    KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "keycloak_secure_123")
    
    # Обновляем .env файл 
    echo "Обновляем .env файл новыми паролями..."
    
    # Создаем временный файл
    cat > .env.tmp << EOF
# PostgreSQL Configuration
POSTGRES_DB=helpdesk
POSTGRES_USER=helpdesk_user
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# MongoDB Configuration
MONGO_ROOT_USERNAME=admin
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
MONGO_DATABASE=helpdesk

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}

# MinIO Configuration
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Keycloak Configuration
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
EOF

    # Заменяем оригинальный файл
    mv .env.tmp .env
    echo "✅ Пароли сгенерированы и сохранены в .env"
fi

# Функция для Docker развертывания
deploy_docker() {
    echo "🐳 Запуск в режиме Docker Compose..."
    
    # Создаем необходимые директории
    echo "📁 Создаем директории конфигурации..."
    mkdir -p config/keycloak config/minio config/postgres

    # Создаем PostgreSQL init скрипт
    cat > config/postgres/init.sql << EOF
-- Создаем базы данных если они не существуют
CREATE DATABASE IF NOT EXISTS keycloak;
CREATE DATABASE IF NOT EXISTS helpdesk;

-- Даем полные права пользователю на обе базы
GRANT ALL PRIVILEGES ON DATABASE keycloak TO helpdesk_user;
GRANT ALL PRIVILEGES ON DATABASE helpdesk TO helpdesk_user;
EOF

    # Загружаем образы
    echo "📥 Загружаем Docker images..."
    docker-compose pull

    # Запускаем сервисы
    echo "🔄 Старт сервисов..."
    docker-compose up -d

    echo "⏳ Ждем когда сервисы станут healthy..."
    sleep 30

    # 🔧 ДОБАВЛЕНО: Настраиваем права доступа в PostgreSQL
    echo "🔧 Настраиваем права доступа в PostgreSQL..."
    
    # Ждем когда PostgreSQL будет готов
    echo "⏳ Ожидаем готовности PostgreSQL..."
    sleep 10
    
    # Даем права на схемы в существующих БД
    echo "📋 Применяем права на схемы..."
    docker exec helpdesk-postgres psql -U postgres -c "
    \c keycloak;
    GRANT ALL ON SCHEMA public TO helpdesk_user;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO helpdesk_user;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO helpdesk_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO helpdesk_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO helpdesk_user;

    \c helpdesk;
    GRANT ALL ON SCHEMA public TO helpdesk_user;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO helpdesk_user;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO helpdesk_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO helpdesk_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO helpdesk_user;
    " || echo "⚠️  Предупреждение: Не удалось применить права на схемы (возможно БД еще не готовы)"

    # Проверяем service status
    echo "🔍 Проверяем статус сервисов..."
    docker-compose ps

    echo ""
    echo "✅ Docker Compose установка выполнена успешно!"
    show_docker_urls
}

# Функция для Kubernetes развертывания
deploy_kubernetes() {
    echo "☸️  Запуск в режиме Kubernetes..."
    
    # Проверяем установлен ли kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl не установлен. Установите kubectl для работы с Kubernetes."
        exit 1
    fi
    
    # Создаем namespace если не существует
    local namespace="helpdesk-infra"
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        echo "📦 Создаем namespace $namespace..."
        kubectl create namespace "$namespace"
    fi
    
    # Загружаем переменные из .env
    source .env
    
    # Создаем секреты
    echo "🔐 Создаем Kubernetes secrets..."
    kubectl create secret generic helpdesk-secrets \
      --namespace="$namespace" \
      --from-literal=postgres-password="$POSTGRES_PASSWORD" \
      --from-literal=mongo-password="$MONGO_ROOT_PASSWORD" \
      --from-literal=redis-password="$REDIS_PASSWORD" \
      --from-literal=minio-password="$MINIO_ROOT_PASSWORD" \
      --from-literal=keycloak-password="$KEYCLOAK_ADMIN_PASSWORD" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    # Применяем манифесты в ПРАВИЛЬНОМ ПОРЯДКЕ
    echo "📋 Применяем Kubernetes манифесты..."
    
    # Функция для безопасного применения манифестов
    apply_manifest() {
        local file="$1"
        if [ -f "$file" ]; then
            echo "  📄 Applying $file"
            kubectl apply -f "$file" -n "$namespace"
        else
            echo "  ⚠️  File not found: $file"
        fi
    }
    
    # 1. Базовые манифесты
    apply_manifest "k8s/base/namespace.yaml"
    apply_manifest "k8s/base/secrets.yaml"
    
    # 2. PVC (должны быть перед Deployment)
    apply_manifest "k8s/postgres/pvc.yaml"
    apply_manifest "k8s/mongodb/pvc.yaml"
    apply_manifest "k8s/redis/pvc.yaml"
    apply_manifest "k8s/minio/pvc.yaml"
    
    # 3. ConfigMaps
    apply_manifest "k8s/postgres/configmap.yaml"
    apply_manifest "k8s/keycloak/configmap.yaml"
    
    # 4. Deployments и Services
    apply_manifest "k8s/postgres/deployment.yaml"
    apply_manifest "k8s/mongodb/deployment.yaml"
    apply_manifest "k8s/mongodb/service.yaml"  # НОВЫЙ СЕРВИС
    apply_manifest "k8s/redis/deployment.yaml"
    apply_manifest "k8s/minio/deployment.yaml"
    apply_manifest "k8s/keycloak/deployment.yaml"
    
    echo "⏳ Ожидаем запуск подов..."
    sleep 10
    
    # Ждем готовности всех подов с таймаутом
    timeout=300
    counter=0
    all_ready=false
    
    while [ $counter -lt $timeout ]; do
        running_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        failed_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l || echo "0")
        
        echo "⏳ Статус: $running_pods/$total_pods подов запущено"
        
        # Показываем статус каждого пода
        kubectl get pods -n "$namespace" --no-headers 2>/dev/null | while read line; do
            pod_name=$(echo "$line" | awk '{print $1}')
            pod_status=$(echo "$line" | awk '{print $3}')
            echo "  📦 $pod_name: $pod_status"
        done
        
        if [ "$failed_pods" -gt 0 ]; then
            echo "❌ Есть упавшие поды. Проверьте логи:"
            kubectl get pods -n "$namespace" 2>/dev/null | grep Failed || true
            break
        fi
        
        if [ "$running_pods" -eq "$total_pods" ] && [ "$total_pods" -ge 5 ]; then
            echo "✅ Все поды готовы!"
            all_ready=true
            break
        fi
        
        sleep 10
        counter=$((counter + 10))
    done
    
    if [ "$all_ready" = false ]; then
        echo "⚠️  Не все поды запустились за отведенное время"
        echo "📋 Текущий статус:"
        kubectl get pods -n "$namespace" 2>/dev/null || echo "Не удалось получить статус подов"
    else
        echo "✅ Все сервисы успешно запущены!"
    fi
    
    show_k8s_urls "$namespace"
}

# Функция показа URLs для Docker
show_docker_urls() {
    echo ""
    echo "📊 Сервисы запущены на:"
    echo "   PostgreSQL:      localhost:5432"
    echo "   MongoDB:         localhost:27017" 
    echo "   Redis:           localhost:6379"
    echo "   MinIO:           localhost:9000 (API), localhost:9001 (Console)"
    echo "   Keycloak:        localhost:8080"
    echo ""
    echo "🔑 Keycloak Admin: http://localhost:8080/admin"
    echo "📦 MinIO Console:  http://localhost:9001"
    echo ""
    echo "🛑 Чтобы остановить сервисы: docker-compose down"
    echo "📈 Посмотреть логи:    docker-compose logs -f"
}

# Функция показа URLs для Kubernetes
show_k8s_urls() {
    local namespace="$1"
    echo ""
    echo "📊 Сервисы запущены в namespace: $namespace"
    echo ""
    echo "🔍 Для доступа к сервисам используйте port-forward:"
    echo "   kubectl port-forward -n $namespace service/postgres 5432:5432 &"
    echo "   kubectl port-forward -n $namespace service/mongodb 27017:27017 &"
    echo "   kubectl port-forward -n $namespace service/redis 6379:6379 &"
    echo "   kubectl port-forward -n $namespace service/minio 9000:9000 9001:9001 &"
    echo "   kubectl port-forward -n $namespace service/keycloak 8080:8080 &"
    echo ""
    echo "📋 Команды управления:"
    echo "   Просмотр подов:    kubectl get pods -n $namespace"
    echo "   Просмотр сервисов: kubectl get svc -n $namespace"
    echo "   Логи:              kubectl logs -n $namespace [pod-name]"
    echo ""
    echo "🛑 Чтобы удалить:     kubectl delete namespace $namespace"
}

# Основная логика
main() {
    if detect_deployment_mode; then
        read -p "🎯 Использовать Kubernetes для развертывания? [y/N]: " use_k8s
        if [[ $use_k8s =~ ^[Yy]$ ]]; then
            deploy_kubernetes
        else
            deploy_docker
        fi
    else
        deploy_docker
    fi
}

# Запуск основной функции
main