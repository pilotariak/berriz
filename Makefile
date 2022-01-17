# Copyright (C) 2021 Nicolas Lamirault <nicolas.lamirault@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR := $(dir $(MKFILE_PATH))

include $(MKFILE_DIR)/commons.mk
include $(MKFILE_DIR)/aws.*.mk

# ====================================
# D E V E L O P M E N T
# ====================================

##@ Development

.PHONY: clean
clean: ## Cleanup
	@echo -e "$(OK_COLOR)[$(BANNER)] Cleanup$(NO_COLOR)"

.PHONY: check
check: check-kubectl check-kustomize check-helm check-flux check-conftest check-kubeval check-popeye ## Check requirements

.PHONY: validate
validate: ## Execute git-hooks
	@poetry run pre-commit run -a

.PHONY: license
license: guard-ACTION ## Check license (ACTION=xxx : fix or check)
	@docker run -it --rm -v $(shell pwd):/github/workspace ghcr.io/apache/skywalking-eyes/license-eye --config /github/workspace/.licenserc.yaml header $(ACTION)


# ====================================
# A W S
# ====================================

##@ AWS

.PHONY: aws-bucket-create
aws-bucket-create: guard-ENV ## Create bucket for bootstrap
	@echo -e "$(OK_COLOR)[$(APP)] Create bucket for bootstrap$(NO_COLOR)"
	@aws s3api create-bucket --bucket aws_$(ENV)-tfstates \
    	--region $(AWS_REGION) \
    	--create-bucket-configuration \
    	LocationConstraint=$(AWS_REGION)

.PHONY: aws-dynamodb-create-table
aws-dynamodb-create-table: guard-ENV ## Create DynamoDB table
	@echo -e "$(OK_COLOR)[$(APP)] Create DynamoDB table$(NO_COLOR)"
	@aws dynamodb create-table \
		--region $(AWS_REGION) \
		--table-name aws_$(ENV)-tfstate-lock \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1

.PHONY: aws-assume-role
aws-assume-role: guard-ENV ## Assume role

.PHONY: aws-secret-version-create
aws-secret-version-create: guard-ENV guard-VERSION # Generate secret
	@echo -e "$(INFO_COLOR)Create the secret for Portefaix version into $(AWS_PROJECT)$(NO_COLOR)"
	@aws secretsmanager create-secret --name portefaix-version \
    	--description "Portefaix version" \
		--tags Key=project,Value=portefaix \
		--tags Key=env,Value=staging \
		--tags Key=service,Value=secrets \
		--tags Key=made-by,Value=awscli \
	    --secret-string $(VERSION)

.PHONY: aws-secret-version-update
aws-secret-version-update: guard-ENV guard-VERSION # Update secret
	@echo -e "$(INFO_COLOR)Update the secret for Portefaix version into $(AWS_PROJECT)$(NO_COLOR)"
	@aws secretsmanager update-secret --secret-id portefaix-version \
		--secret-string $(VERSION)


# ====================================
# T E R R A F O R M
# ====================================

##@ Terraform

.PHONY: terraform-init
terraform-init: guard-SERVICE guard-ENV ## Plan infrastructure (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Init infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/terraform \
		&& terraform init -upgrade -reconfigure -backend-config=backend-vars/$(ENV).tfvars

.PHONY: terraform-plan
terraform-plan: guard-SERVICE guard-ENV ## Plan infrastructure (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Plan infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/terraform \
		&& terraform init -upgrade -reconfigure -backend-config=backend-vars/$(ENV).tfvars \
		&& terraform plan -var-file=tfvars/$(ENV).tfvars

.PHONY: terraform-apply
terraform-apply: guard-SERVICE guard-ENV ## Builds or changes infrastructure (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Apply infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/terraform \
		&& terraform init -upgrade -reconfigure -backend-config=backend-vars/$(ENV).tfvars \
		&& terraform apply -var-file=tfvars/$(ENV).tfvars

.PHONY: terraform-destroy
terraform-destroy: guard-SERVICE guard-ENV ## Builds or changes infrastructure (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Apply infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/terraform \
		&& terraform init -upgrade -reconfigure -backend-config=backend-vars/$(ENV).tfvars \
		&& terraform destroy -lock-timeout=60s -var-file=tfvars/$(ENV).tfvars

.PHONY: terraform-tflint
terraform-tflint: guard-SERVICE ## Lint Terraform files
	@echo -e "$(OK_COLOR)[$(APP)] Lint Terraform code$(NO_COLOR)" >&2
	@cd $(SERVICE)/terraform \
		&& tflint \
		--enable-rule=terraform_deprecated_interpolation \
		--enable-rule=terraform_deprecated_index \
		--enable-rule=terraform_unused_declarations \
		--enable-rule=terraform_comment_syntax \
		--enable-rule=terraform_documented_outputs \
		--enable-rule=terraform_documented_variables \
		--enable-rule=terraform_typed_variables \
		--enable-rule=terraform_naming_convention \
		--enable-rule=terraform_required_version \
		--enable-rule=terraform_required_providers \
		--enable-rule=terraform_unused_required_providers \
		--enable-rule=terraform_standard_module_structure

.PHONY: terraform-tfsec
terraform-tfsec: guard-SERVICE ## Scan Terraform files
	@echo -e "$(OK_COLOR)[$(APP)] Lint Terraform code$(NO_COLOR)" >&2
	@cd $(SERVICE)/terraform \
		&& tfsec \

.PHONY: tfcloud-validate
tfcloud-validate: guard-SERVICE guard-ENV ## Plan infrastructure (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Init infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/$(ENV) \
		&& rm -fr .terraform \
		&& terraform init \
		&& terraform validate

.PHONY: tfcloud-init
tfcloud-init: guard-SERVICE guard-ENV ## Plan infrastructure using Terraform Cloud (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Init infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/$(ENV) && terraform init

.PHONY: tfcloud-plan
tfcloud-plan: guard-SERVICE guard-ENV ## Plan infrastructure using Terraform Cloud (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Plan infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/$(ENV) \
		&& terraform init \
		&& terraform plan

.PHONY: tfcloud-apply
tfcloud-apply: guard-SERVICE guard-ENV ## Apply infrastructure using Terraform Cloud (SERVICE=xxx ENV=xxx)
	@echo -e "$(OK_COLOR)[$(APP)] Plan infrastructure$(NO_COLOR)" >&2
	@cd $(SERVICE)/$(ENV) \
		&& terraform init \
		&& terraform apply
