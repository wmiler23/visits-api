# Visits API: GitHub Actions CI/CD to AWS with CloudFormation

Course project. A tiny HTTP API (API Gateway HTTP API, Lambda, DynamoDB) whose
real subject is the pipeline around it:

- **Every pull request**: cfn-lint, shellcheck, actionlint and pytest (`ci.yml`), plus a
  CloudFormation change set preview posted on the PR when `infra/` changes (`pr-preview.yml`).
- **Every merge to main**: one Lambda bundle is built, deployed to **dev** and smoke tested,
  then deployed to **prod** as soon as dev passes (`deploy.yml`).
- **No AWS access keys anywhere.** GitHub OIDC tokens are exchanged for one-hour credentials,
  and the role a job gets depends on its GitHub environment.

## Layout

```
.github/workflows/  ci.yml, deploy.yml, pr-preview.yml
bootstrap/          account.yaml, environment.yaml  (deployed once, by hand)
infra/              template.yaml + params/<env>.params  (deployed by the pipeline)
src/app/handler.py  the Lambda function
tests/              unit tests (DynamoDB mocked with moto)
scripts/            everything the workflows run, runnable from a laptop too
Makefile            make check | package | bootstrap | github | teardown
```

## Quick start

```bash
git init -b main
python3 -m venv .venv && source .venv/bin/activate
make install check                       # lint + tests, no AWS needed

gh repo create visits-api --public       # empty repo; its IDs go into the trust policies
git remote add origin "https://github.com/$(gh api user --jq .login)/visits-api.git"
export AWS_PROFILE=<admin-profile> AWS_REGION=us-east-1
make bootstrap                           # three bootstrap stacks in AWS
make github                              # environments, secrets, branch protection
git add -A && git commit -m "Visits API and pipeline"
git push -u origin main                  # first deploy: dev, then prod
```

Then watch both deployments in the Actions tab. The course document walks
through every file and every step.

## Tear down

```bash
make teardown
```
