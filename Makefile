.PHONY: up down build restart logs shell seed reset status

## Levantar todos los servicios en background
up:
	docker compose up -d

## Detener los servicios (conserva los volúmenes)
down:
	docker compose down

## Reconstruir la imagen desde cero (sin cache)
build:
	docker compose build --no-cache

## Reiniciar solo el servicio API (sin reconstruir)
restart:
	docker compose restart api

## Ver logs en tiempo real del API
logs:
	docker compose logs -f api

## Abrir una shell dentro del contenedor API
shell:
	docker compose exec api sh

## Cargar datos de demostración (usuarios, módulos, estaciones, pantalla)
seed:
	docker compose exec api node apps/api/db/seeds/demo_seed.js

## DESTRUYE los volúmenes y reinicia desde cero (borra la BD)
reset:
	docker compose down -v
	docker compose up -d

## Ver estado de los contenedores
status:
	docker compose ps
