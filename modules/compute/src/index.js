const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
} = require("@aws-sdk/lib-dynamodb");

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.TABLE_NAME;

exports.handler = async (event) => {
  const method = event.requestContext?.http?.method || "GET";

  try {
    if (method === "GET") {
      const id = event.queryStringParameters?.id;
      if (!id) {
        return response(400, { error: "Missing id query parameter" });
      }
      const result = await docClient.send(
        new GetCommand({ TableName: TABLE_NAME, Key: { id } })
      );
      return response(200, result.Item || {});
    }

    if (method === "POST") {
      const body = JSON.parse(event.body || "{}");
      if (!body.id) {
        return response(400, { error: "Missing id in request body" });
      }
      await docClient.send(
        new PutCommand({ TableName: TABLE_NAME, Item: body })
      );
      return response(201, { status: "created", id: body.id });
    }

    return response(405, { error: "Method not allowed" });
  } catch (err) {
    console.error(err);
    return response(500, { error: "Internal server error" });
  }
};

function response(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
