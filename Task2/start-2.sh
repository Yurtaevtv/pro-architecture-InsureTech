#!/bin/bash
set -e  # Останавливать скрипт при любой ошибке

echo "====== Пересоздаем minikube ======"

minikube delete

# Запуск minikube с достаточными ресурсами для Istio
minikube start
minikube addons enable metrics-server

# Установка istioctl если не установлен
if ! command -v istioctl &> /dev/null; then
    echo "Istioctl не установлен. Запускаем установку"
    curl -L https://istio.io/downloadIstio | sh -
    cd istio-*
    export PATH=$PWD/bin:$PATH
    cd ..
fi

# Установка Istio с демо-профилем и всеми компонентами
echo "====== Устанавливаем Istio ======"
istioctl install --set profile=demo \
  --set meshConfig.accessLogFile=/dev/stdout \
  -y

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.23/samples/addons/prometheus.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring \
  --create-namespace \
  -f ./k8s/values.yaml
  
# Ждем готовности Istio компонентов
echo "====== Ожидаем готовности Istio ======"
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s

# Проверка установки
kubectl get pods -n istio-system

# Включаем автоматическое внедрение sidecar
kubectl label namespace default istio-injection=enabled --overwrite

echo "====== Пересобираем контейнеры приложений ======"

# Переключаемся на docker daemon minikube
eval $(minikube docker-env)

# Сборка образа
docker build -t testapp:latest ./scaletestapp

# Для Minikube образ уже доступен, но дополнительно загружаем
minikube image load testapp:latest

echo "====== Применяем манифест k8s ======"

# Создаем namespace если нужно
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -

# Применяем deployment
kubectl apply -f ./k8s/deployment.yml

# Ждем готовности Pod'а с sidecar
echo "====== Ожидаем запуска Pod'а ======"
sleep 10
kubectl wait --for=condition=ready pod -l app=test-deployment-app --timeout=120s

# Проверка наличия Pod'а
if kubectl get pods -l app=test-deployment-app | grep -q Running; then
  echo "✅ Тест контейнер найден и работает"
  kubectl get pods -l app=test-deployment-app
else
  echo "❌ Тест контейнер не найден или не запущен"
  kubectl get pods -l app=test-deployment-app
  exit 1
fi

echo "====== Настройка мониторинга и маршрутизации ======"

# Применяем Service (должен быть до DestinationRule)
kubectl apply -f ./k8s/service.yml

# Ждем готовности Service
sleep 5

# Применяем Prometheus конфигурацию
# kubectl apply -f ./k8s/prometheus.yml

# Применяем DestinationRule (теперь CRDs должны быть установлены)
if kubectl apply -f ./k8s/destination.yml; then
  echo "✅ DestinationRule применен"
else
  echo "❌ Ошибка применения DestinationRule"
  kubectl get crd | grep destinationrule
  exit 1
fi

# Применяем HPA
kubectl apply -f ./k8s/hpa-custom-metrics-2.yaml

echo "====== Проверка сервисов ======"

# Проверка Service
kubectl get svc scale-test-service

# Создаем тестовый Pod для проверки доступа
echo "====== Тестируем доступ к сервису ======"
kubectl run test-pod --rm -it --restart=Never --image=busybox -- wget -qO- http://scale-test-service:8080 || echo "Тест доступа завершен"

# Проксирование порта в фоне
echo "====== Настраиваем port-forward ======"
echo "Запуск port-forward в фоне..."
kubectl port-forward svc/scale-test-service 8080:8080 &
PF_PID=$!

echo ""
echo "====== Деплой завершен успешно! ======"
echo "Для доступа к приложению:"
echo "  - Локально: http://localhost:8080"
echo "  - В кластере: http://scale-test-service.default.svc.cluster.local:8080"
echo ""
echo "Для доступа к Kiali (визуализация сервис-меша):"
echo "  kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "  Затем откройте http://localhost:20001"
echo ""
echo "Для остановки port-forward выполните: kill $PF_PID"

# Ждем сигнала завершения
wait $PF_PID