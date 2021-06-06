CMS_CONTAINER_NAME?=$(shell basename $(CURDIR))_cms-php_1
PWA_CONTAINER_NAME?=$(shell basename $(CURDIR))_pwa-node_1

.PHONY: dev prod build clean composer craft yarn update update-clean up

dev: up

prod: up

build: up
	docker-compose exec pwa-node yarn run build

clean:
	docker-compose down --volumes
	docker-compose up --build

composer: up
	docker-compose exec cms-php composer $(filter-out $@,$(MAKECMDGOALS))

craft: up
	docker-compose exec cms-php php craft $(filter-out $@,$(MAKECMDGOALS))

yarn: up
	docker-compose exec pwa-node yarn $(filter-out $@,$(MAKECMDGOALS))

#pulldb: up
#	cd scripts/ && ./docker_pull_db.sh
#
#restoredb: up
#	cd scripts/ && ./docker_restore_db.sh $(filter-out $@,$(MAKECMDGOALS))

update:
	docker-compose down

	# Update Docker images
	docker-compose pull
	docker-compose build

	# Update dependencies
	docker-compose run cms-php composer update --no-scripts --no-progress --optimize-autoloader --no-interaction
	docker-compose run cms-php php craft update
	docker-compose run pwa-node /bin/bash -c 'yarn install && yarn upgrade'

	docker-compose up

update-clean:
	docker-compose down

	rm -f cms/composer.lock
	rm -rf cms/vendor/

	rm -f pwa/yarn.lock
	rm -rf pwa/node_modules/

	docker-compose up

up:
	if [[ ! "$$(docker ps -q -f name=${CMS_CONTAINER_NAME})" ]]; then \
        docker-compose up; \
    fi

%:
	@:
# ref: https://stackoverflow.com/questions/6273608/how-to-pass-argument-to-makefile-from-command-line
