#!/bin/bash

set -e

echo "🚀 Starting Smart HelpDesk Infrastructure Setup..."
echo "================================================"

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
    echo "📝 Creating .env file from .env.example..."
    cp .env.example .env
    echo "⚠️  Please edit .env file with your actual passwords!"
fi

# Генерируем рандомные пароли если .env пустой (исправленная версия)
if [ ! -s .env ] || grep -q "strong_password_here" .env; then
    echo "🔐 Generating secure passwords..."
    
    # Generate random passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "postgres_secure_123")
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "mongo_secure_123") 
    REDIS_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "redis_secure_123")
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "minio_secure_123")
    KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "keycloak_secure_123")
    
    # Обновляем .env файл (кроссплатформенный способ)
    echo "Updating .env file with secure passwords..."
    
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
    echo "✅ Passwords generated and saved to .env"
fi

# Создаем необходимые директории
echo "📁 Creating configuration directories..."
mkdir -p config/keycloak config/minio config/postgres

# Создаем PostgreSQL init скрипт
cat > config/postgres/init.sql << EOF
CREATE DATABASE keycloak;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO helpdesk_user;
EOF

# Загружаем образы
echo "📥 Pulling Docker images..."
docker-compose pull

# Запускаем сервис
echo "🔄 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be healthy..."
sleep 30

# Проверяем service status
echo "🔍 Checking service status..."
docker-compose ps

echo ""
echo "✅ Setup completed successfully!"
echo ""
echo "📊 Services are running on:"
echo "   PostgreSQL:      localhost:5432"
echo "   MongoDB:         localhost:27017"
echo "   Redis:           localhost:6379"
echo "   MinIO:           localhost:9000 (API), localhost:9001 (Console)"
echo "   Keycloak:        localhost:8080"
echo ""
echo "🔑 Keycloak Admin: http://localhost:8080/admin"
echo "📦 MinIO Console:  http://localhost:9001"
echo ""
echo "🛑 To stop services: docker-compose down"
echo "📈 To view logs:    docker-compose logs -f"