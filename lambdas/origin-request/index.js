exports.handler = (event, context, callback) => {
  const { request } = event.Records[0].cf;

  try {
    const host = request.headers['x-forwarded-host'][0].value;
    const branch = host.match(/^preview-([^\.]+)/)[1];
    request.origin.custom.path = `/${branch}`;
  } catch (e) {
    request.origin.custom.path = `/master`;
  }

  return callback(null, request);
};
