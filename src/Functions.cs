using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using Azure.Core;
using Azure.Storage.Blobs.Specialized;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Blobs;
using Azure.Storage;
using Azure.Identity;
using System.IO;
using Azure.Storage.Sas;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Management.Fluent;
using Microsoft.Azure.Management.ResourceManager.Fluent;
using Microsoft.Azure.Management.ResourceManager.Fluent.Authentication;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;
using System.Text.RegularExpressions;

namespace TUMWorkshop
{
    public static class Functions
    {
        private static readonly Regex regex = new Regex("^[a-zA-Z0-9!@#$%&]*$");
        private static readonly Lazy<IDictionary<string, BlobServiceClient>> _serviceClients = new Lazy<IDictionary<string, BlobServiceClient>>(() => new Dictionary<string, BlobServiceClient>());
        private static readonly Lazy<TokenCredential> _msiCredential = new Lazy<TokenCredential>(() =>
        {
            // https://docs.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential?view=azure-dotnet
            // Using DefaultAzureCredential allows for local dev by setting environment variables for the current user, provided said user
            // has the necessary credentials to perform the operations the MSI of the Function app needs in order to do its work. Including
            // interactive credentials will allow browser-based login when developing locally.
            return new Azure.Identity.DefaultAzureCredential(includeInteractiveCredentials: true);
        });

        private static readonly Lazy<IAzure> _legacyAzure = new Lazy<IAzure>(() =>
        {
            // If we find tenant and subscription in environment variables, configure accordingly
            if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(@"AZURE_TENANT_ID"))
                && !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(@"AZURE_SUBSCRIPTION_ID")))
            {
                var tokenCred = _msiCredential.Value;
                var armToken = tokenCred.GetToken(new TokenRequestContext(scopes: new[] { "https://management.azure.com/.default" }, parentRequestId: null), default).Token;
                var armCreds = new Microsoft.Rest.TokenCredentials(armToken);

                var graphToken = tokenCred.GetToken(new TokenRequestContext(scopes: new[] { "https://graph.windows.net/.default" }, parentRequestId: null), default).Token;
                var graphCreds = new Microsoft.Rest.TokenCredentials(graphToken);

                var credentials = new AzureCredentials(armCreds, graphCreds, Environment.GetEnvironmentVariable(@"AZURE_TENANT_ID"), AzureEnvironment.AzureGlobalCloud);

                return Microsoft.Azure.Management.Fluent.Azure
                    .Authenticate(credentials)
                    .WithSubscription(Environment.GetEnvironmentVariable(@"AZURE_SUBSCRIPTION_ID"));
            }
            else
            {
                var credentials = SdkContext.AzureCredentialsFactory
                    .FromSystemAssignedManagedServiceIdentity(MSIResourceType.AppService, AzureEnvironment.AzureGlobalCloud);
                return Microsoft.Azure.Management.Fluent.Azure
                    .Authenticate(credentials)
                    .WithDefaultSubscription();
            }
        });

        [FunctionName(nameof(GetBlob))]
        public static IActionResult GetBlob(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequest req,
            ILogger log)
        {
            var queryParams = req.GetQueryParameterDictionary();

            if (!queryParams.TryGetValue(@"blobUri", out string blobUriString) || string.IsNullOrWhiteSpace(blobUriString)
            || !regex.IsMatch(blobUriString)
            )
            {
                return new BadRequestObjectResult($@"Request must contain query parameter 'blobUri' designating the name of the file to download");
            }
            string fileEndpoint = "https://STORAGEACCOUNTNAME.blob.core.windows.net/public/" + blobUriString + ".jpg";

            BlockBlobClient containerClient = new BlockBlobClient(new Uri(fileEndpoint), new DefaultAzureCredential());

            try
            {
                var memoryStream = new MemoryStream();
                containerClient.DownloadTo(memoryStream);
                //string downloadedData = downloadResult.Content.ToString();
                memoryStream.Position = 0;
                return new FileStreamResult(memoryStream, "image/jpeg");
            }
            catch (Exception e)
            {
                log.LogError(e, $@"Failure in retreiving URL for '{blobUriString}'");
                return new ObjectResult(e)
                {
                    StatusCode = (int)HttpStatusCode.BadGateway
                };
            }
        }
    }
}
