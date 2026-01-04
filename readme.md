To get your infrastructure automation running, you need to generate two different types of credentials: the Infrastructure Keys (for the Infisical server itself) and the Machine Identity (for your automation script to log in).

Here is the step-by-step guide to generating both.

1. Generate the Infrastructure Keys (openssl)
These two keys are required for the Infisical container to start up and encrypt its internal database. Run these commands in your terminal:

For INFISICAL_ENCRYPTION_KEY: Bash

```
    openssl rand -hex 32
```

For INFISICAL_AUTH_SECRET: Bash

```
    openssl rand -base64 32
```

Copy the output of each and paste them into your .env file.