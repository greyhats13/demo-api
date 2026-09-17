# REVIEW.md

Review of the demo-api repo like a PR review. Findings are grouped by priority, each one: what's wrong, why it matters and the proposed fix. The status table after the finding show which fix I already implemented in this branch, and the assumptions I take.

## Assumptions

These resources already exist and are managed outside this repo. The pipeline and terraform only reference them through Github repository variables:

- S3 bucket for terraform state → `vars.TF_STATE_BUCKET`
- ACM certificate for the ALB HTTPS listener → `vars.ACM_CERTIFICATE_ARN`
- SSM Parameter Store holding DB password → `vars.DB_PASSWORD_PARAMETER_ARN`
- IAM role for Github Actions OIDC + Github OIDC identity provider → `vars.AWS_ROLE_ARN`

## Blockers

**1. Credentials commited and hardcoded in many file** 
The production DB password is hardcoded and commited in 5 fplace: `.env`. THe DOckerfile, terraform variable default, the app code and task definition. So the password is in git history, image layers, tfstate, the ECS console. We must treat it as leaked and rotated it.  
**Fix:** delete all 5 copies, change to `.env.example` (with dummy value) and ignore `.env` in git, then inject DB password from SSM Parameter Store at runtime

**2. ECS task role has Administrator access and is reused as execution role**
If the app is compromised, the attacker can do anything in the AWS account, so the blast radius is the whole account.  
**Fix:** split into 2 roles with least privilege: the task execution role should have the ECS Task Execution managed policy and permission to read SSM Parameter Store, the task role has no policy at all (the app calls no AWS API).

**3. Everything reachable from the internet**  
THe ALB and the task share 1 Security Group(SG) so that's open to the internet on all port, so traffic can bypass the ALB and reach the container directly. Outbound is open on all ports too, so a compromised container can call out anywhere.  
**Fix:** split into 2SG: ALB SG can accept HTTP and HTTPS from internet, app SG only accept the app port from the ALB SG and only allow outbount HTTPS to the AWS API.

**4. Production run the Flask dev server with `debug=True`**  
With debug on, any unhandled exception will open the Wekzeug debugger, which give attacker remote code execution on the container. THe dev server is not made for productiont raffic.  
**Fix:** run the app with production WSGI server(gunicorn) in the image, so the dev server never run.  

**5. Pipline deploy even when test fail and the test fail**  
`continue-on-error: true` so the test run but the result is ignored, a red test cant stop the deploy. And the test fail now because `app/` is not a package. So, the pipeline is green while a real test broken.  
**Fix:** make `app` a package (by adding `__init__.py`) so the test import works, run the test from repo root and remove `continue-on-error` so a red test stop the deploy. 

**6. Deploy with mutable latest tag, rollback is not possible**  
Everything push and pull `:latest`, so we cant tell which code run, tasks can run different code after restart and rollback is impossible because the previous image is overwritten.  
**Fix:** tag with the commit SHA, make the ECR tags immutable and deploy by registreing a new task definition revision with the commit SHA tag image.

**7. Terraform apply with auto approve in CI with local state**  
No backend means state is only on the runner and gone after the job: every run start empty and try to recreate existing resources, two push can run at the same time and no body review the plan.  
**Fix:** use a remote S3 backend with statke locking, run fmt/validate/plan before apply and make sure 2 run cant overlap

## Should-fix

**8. Zero observability**  
No log configuration, when a task crash on boot we get "task stopped", no traceback, no reason, and no alarm too, so we cant tell wheter the service is down or not.  
**Fix:** send container logs to a CloudWatch log group with retention, and alarm on ALB 5xx and unhealthy host count metrics.

**9. No deployment safety on the ECS service**
No circuit breaker, the healthcheck us the default path insted of the `/health` endpoint and the default dereigstration delay is too long. A bad deploy keep replacing task forever.  
**Fix:** enable the deployment circuit breaker with auto-rollback, point the healthcheck to `/health`, lower the deregistration delay and give the task healthcheck grace period.

**10. Long-lived AWS credentials in the pipeline**  
Static keys never expire and at job level every step can read them, including 3rd party github action. No a blocker only because they are encrypted in Github secrets.  
**Fix:** switchto OIDC so the job assume a shortlived role and store no static key at all.

**11. Dockerfile quality**  
`python:latest` can change anytime while CI test on 3.13, we test on 1 version but ship another version. The build copy all the repo into the image, so `.env` and infra go iinsude too, run as root and the full debian based (around 1GB) which mean bigger attack surface, CVE,slow task start, etc.  
**FIx:** optimize and harden the image with multistage build andand distroless nonroot, copy only the app code, pin the base image and use the same python version in CI.  

**12. No TLS on the ALB**  
HTTP only, so data is not encrypted in transit.  
**Fix:** add HTTPS listener with an ACM certificate and redirect HTTP to HTTPS.

**13. Single task = single point of failure**  
Only 1 task run, no HA. So 1 bad task or 1 AZ issue means downtime.  
**Fix:** run at least 2 tasks across the 2 AZs.

**14. Pipeline cant actually run as written**  
There's no ECR login step, the account is a placeholder and the same name ar harcoded in many github action steps.  
**Fix:** add ECR login step, take the registry from its output, define the name and region once in the workflow

**15. No CI before merge**  
Everything run only on push to `main`, after the code is merged.  
**Fix:** run tests and terraform fmt/validate/plan on pull request too, keep deploy only on push to `main`.

**16. ECS service creation race in terraform**  
The service references the target group but nothing makes it wait until the listener attaches the TG to the ALB, so first apply can fail randomly.  
**Fix:** add an explicit `depends_on` the listener.

**17. Unpinned python dependencies**  
`requirements.txt`  has no version, so every build install the latest version from PyPI. The same commit can give a different image and bad or malicious release reach production with no review.  
**Fix:** pin the version of every dependency, gunicorn included.

## Nice-to-have

**18. ECR hygiene**  
No vulnerability scan and untagged images keep growing.  
**Fix:** enable image scan on push and add a lifecycle policy to expire untagged images.

**19. Terraform project hygiene**
THe terraform version is not pinned, the AZ names are built by string concat instead of data source, no tags on resources, no outputs, and terraform artifacts are not ignored in git.  
**Fix:** pin the terraform version, take the AZ names from the `aws_availability_zones` data source, ignore terraform artifacts in git, add default tags on all resources and output the ALB DNS name.

**20. Private subnets, NAT and VPC Endpoints for the task**
The task still have a public IP and route to internet, only the SG blocks inbound. private subnet + NAT is defense in depth, because 1 wrong SG rule later cant expose them.
**Fix:** move the task to priovate subnet, NAT gateway for outbound and VPC endpoints for AWS API so traffic stay private. So the task have no public IP and no route from the internet.  

**21. ALB access logs, VPC flow logs, deletion protection**  
No request audit trail and the ALB can be deleted by accident.  
**Fix:** enable ALB access logs and VPC flow logs and turn on deletion protection on the ALB.

**22. No autoscaling**  
The task count is fixed, so nothing handles load spike.  
**Fix:** add application autoscaling with target tracking on CPU.

**23. Workflow hardening**  
Actions are pinned only by tag, no job timeout, no protected environment and 2 run can overlap.  
**Fix:** make sure 2 runs cant overlap (also part of finding 7), pin the actions to commit SHA, set a job timeout and add Github environment for prod approval.

## How we know it is down and how we roll back

The ALB health check hits `/health` on every task, when task fail the check the ALB stops sending traffic to it and if all targets fail the ALB returns 5xx, target health in the consle (or `aws elbv2 describe-target-health`) is the first place we check and the container logs are in the CloudWatch group `/ecs/demo-api`. During a deploy, the circuit breaker detect task that never become healthy, stop the rollout and rolls back to the last working revision by itself. The next step is in finding 8: CloudWatch alarms on ALB 5xx and UnHealthyHostCount going to SNS, so we get alert instead of user complain first. For rollback of a bad deploy that passed health checks: every image is tagged with the commit SHA and ECR is immutable, so the previous image still exist, we redeploy the previous task definition revision (`aws ecs update-service --task-definition demo-api:<previous-rev>`), or rerun the pipeline from the last good commit. We dont need to rebuild the image and nothing is overwritten.

## Evidence

`terraform fmt -check` and `terraform validate` from `infra/` (init with `-backend=false`, no AWS needed):

```sh
greyhats13@greyhats13 infra % terraform fmt -check
greyhats13@greyhats13 infra % terraform init -backend=false
Initializing provider plugins found in the configuration...
- Reusing previous version of hashicorp/aws from the dependency lock file
- Using previously-installed hashicorp/aws v5.100.0




Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
greyhats13@greyhats13 infra % terraform validate
Success! The configuration is valid.
```

Image size before and after the Dockerfile change (`docker images`):

```
greyhats13@greyhats13 infra % docker images
                                                                                                             i Info →   U  In Use
IMAGE                                        ID             DISK USAGE   CONTENT SIZE   EXTRA
demo-api:after                               dfc2453508bb       80.2MB             0B        
demo-api:before                              c7b21bc5d23b       1.14GB             0B    
```

Tests (same invocation as the pipeline):
```sh
(venv) greyhats13@greyhats13 demo-api % python -m pytest app/ -v    
====================================================== test session starts ======================================================
platform darwin -- Python 3.14.6, pytest-9.1.1, pluggy-1.6.0 -- /Users/greyhats13/git/solveeducation/demo-api/venv/bin/python
cachedir: .pytest_cache
rootdir: /Users/greyhats13/git/solveeducation/demo-api
collected 2 items                                                                                                               

app/test_app.py::test_health PASSED                                                                                       [ 50%]
app/test_app.py::test_index PASSED                                                                                        [100%]

======================================================= 2 passed in 0.10s =======================================================
```

Local smoke test of the new image (gunicorn on distroless, not the dev server):

```sh
greyhats13@greyhats13 demo-api % docker run -d -p 8080:8080 --name demo-api demo-api:after
71f587c35386603d479e38dda1c371c3f2b4af0bf0ea4a3da3b964afc55bb33e
greyhats13@greyhats13 demo-api % curl -s http://localhost:8080/health                     
{"status":"ok"}
greyhats13@greyhats13 demo-api % curl -s http://localhost:8080   
{"message":"Hello from the API","version":"1.0.0"}
greyhats13@greyhats13 demo-api % docker logs -f 71f587c35386603d479e38dda1c371c3f2b4af0bf0ea4a3da3b964afc55bb33e
[2026-08-05 03:42:38 +0000] [1] [INFO] Starting gunicorn 26.0.0
[2026-08-05 03:42:38 +0000] [1] [INFO] Listening at: http://0.0.0.0:8080 (1)
[2026-08-05 03:42:38 +0000] [1] [INFO] Using worker: sync
[2026-08-05 03:42:38 +0000] [7] [INFO] Booting worker with pid: 7
[2026-08-05 03:42:38 +0000] [8] [INFO] Booting worker with pid: 8
[2026-08-05 03:42:39 +0000] [1] [INFO] Control socket listening at /home/nonroot/.gunicorn/gunicorn.ctl
192.168.65.1 - - [05/Aug/2026:03:43:07 +0000] "GET /health HTTP/1.1" 200 16 "-" "curl/8.7.1"
192.168.65.1 - - [05/Aug/2026:03:43:14 +0000] "GET / HTTP/1.1" 200 51 "-" "curl/8.7.1"
192.168.65.1 - - [05/Aug/2026:03:44:07 +0000] "GET / HTTP/1.1" 200 51 "-" "curl/8.7.1"
```


## With more time
### From not-implemented finding
- CloudWatch alarms (ALB 5xx, UnHealthyHostCount) + SNS to email or Slack — finding 8, so we get the alert instead of user complain first.
- Private subnets with a NAT gateway for outbound and VPC endpoints for ECR, logs and SSM — finding 20, so the task have no public IP and the AWS API traffic stay private inside AWS network.
- ECR lifecycle policy, `default_tags`, container insights, autoscaling, ALB access logs + VPC flow logs — findings 18, 19, 21, 22.
- Pin Github Actions to commit SHA, add `timeout-minutes` and  protected `production` environment — finding 23.
### Improvements
- Split terraform into modules with per environment state, so infra change can be tested in dev before it goes to prod.
- Split the pipeline for infra.yml (network, ALB, ECS Cluster), service.yml (ECS Service, Task definition, Task role, Target group, Listener rule, etc) and deploy.yml (CI/CD for apps).
- Self service model, so plan and apply happen from the pull request and infra change follow the same review flow as code.
- Canary deploy with CodeDeploy, so traffic shift slowly and roll back on alarm, instead of replacing all tasks at once.
- WAF on the ALB, to rate limit and block common attacks on a public API.

## What I implemented in this branch

I had around 50 minutes for terraform & the pipeline, so I fix by risk order first.

| Finding | Status | Why |
|---|---|---|
| 1-7 (all blockers) | implemented | highest risk, cant go to production like this |
| 8 | partial: logs yes, alarms no | log group is 1 resource, alarms + SNS need more time |
| 9-17 | implemented | small changes, big risk cut |
| 18 | partial: scan on push yes, lifecycle no | scan is 1 line on a resource I already touch, lifecycle policy saves cost not risk |
| 19 | partial: version & gitignore yes, AZ data source, tags & outputs no | the 2 I did are free, the rest is polish |
| 20 | not implemented | This is not critical at the moment, The SG already block inbvound |
| 21-22 | not implemented | no real risk cut inside our time budget |
| 23 | partial: concurrency yes, rest no | concurrency belongs to finding 7, the rest is polish |

Every "not implemented" & "no" above is also in the with-more-time list.