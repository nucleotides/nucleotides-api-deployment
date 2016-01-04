# Nucleotid.es API deployment

This software tests and deploys the nucleotides API. The nucleotid.es stack is
tested as a whole as it would be run in production to ensure that any possible
production issues are caught in staging first. This is done by creating the
nucleotid.es stack as a staging environment, and running integration tests
against this.

## Steps

  * Create a temporary AWS postgres database in RDS. This database is used for
    running the integration tests and is removed afterwards.

  * Create a temporary container from the nucleotides API image.

  * Run integration tests against the staged version of the API.

  * If all tests pass, run the migrations for the production version of the
    database and redeploy the API container with the latest master version.
