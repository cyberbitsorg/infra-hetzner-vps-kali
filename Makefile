.PHONY: help fmt validate lint test image destroy-all

help:            ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n",$$1,$$2}'

fmt:             ## Format Tofu files
	tofu fmt -recursive

validate:        ## Validate Tofu config
	tofu init -backend=false >/dev/null && tofu validate

lint:            ## Lint shell + Ansible
	shellcheck scripts/lib/*.sh
	ansible-lint ansible/ || true
	ansible-playbook -i ansible/inventory/terraform.py ansible/playbook.yaml --syntax-check

test:            ## Run shell unit tests
	bash tests/run.sh

image:           ## Phase 0: build the Kali snapshot via Packer (one-time)
	cd packer && packer init . && packer build .

destroy-all:     ## Destroy everything, including the prevent_destroy'd /home volume
	sed -i.bak 's/prevent_destroy = true/prevent_destroy = false/' main.tf && rm -f main.tf.bak
	tofu destroy
	git checkout -- main.tf
