# Build feature environments in AWS with CloudFront and S3 using wildcard domains

This repo contains the Terraform code to build a CDN with feature branch subdomains.

Article => https://medium.com/@nedknowles/preview-environments-in-aws-with-cloudfront-and-lambda-edge-7acccb0b67d1

I've set out the HCL code to be as easy to read as possible, it's not meant to represent a final project structure,instead it should serve to help new engineers understand the bare bones of what's needed.
 
The core steps to enable this is as follows:

1. Enable wildcard certificate and cdn.

2. Put S3 objects prefixed by branch name or pr number

3. Add a `viewer-request` lambda to CloudFront. This will make sure the `host` from the `viewer-request` is passed to the `origin-request` by way of the `x-forwarded-host` header.

```js
exports.handler = (event, context, callback) => {
  const { request } = event.Records[0].cf;

  request.headers['x-forwarded-host'] = [
    { key: 'X-Forwarded-Host', value: request.headers.host[0].value }
  ];

  return callback(null, request);
};
```

4. Make sure the `x-forwarded-host` header is forwarded in CloudFront so that the `origin-request` lambda can see it.

```hcl-terraform
forwarded_values {
  query_string = false
  headers      = ["x-forwarded-host"] # <-- IMPORTANT

  cookies {
    forward = "none"
  }
}
```

5. Add a `origin-request` lambda that sets the s3 path to prefix with the feature branch slug.

```js
exports.handler = (event, context, callback) => {
  const { request } = event.Records[0].cf;

  try {
    const host = request.headers['x-forwarded-host'][0].value;
    const branch = host.match(/^preview-([^\.]+)/)[1]; // <-- Check domain prefix
    request.origin.custom.path = `/${branch}`;
  } catch (e) {
    request.origin.custom.path = `/master`; // <-- Default to master
  }

  return callback(null, request);
};
```

6. Add the lambdas to the CloudFront cache behavior (if you have multiple you'll need to add it to each one)

```hcl-terraform
lambda_function_association {
  event_type   = "origin-request"
  lambda_arn   = module.origin_request_lambda.qualified_arn
  include_body = false
}

lambda_function_association {
  event_type   = "viewer-request"
  lambda_arn   = module.viewer_request_lambda.qualified_arn
  include_body = false
}
```

7. Finally, add a CNAME alias to the CDN for the wildcard domain name
