module Systemdnetes.ApiSpec (tests) where

import Data.Aeson (encode)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Network.HTTP.Types (Status, status200, status201, status400, status404, status405)
import Network.Wai (defaultRequest)
import Network.Wai.Internal (Request (..), Response (..))
import Systemdnetes.Api (handleRequest)
import Systemdnetes.App (PureResult (..), defaultPureConfig, runAppPure)
import Systemdnetes.App qualified as App
import Systemdnetes.Domain.Node (Node (..), NodeName (..))
import Systemdnetes.Domain.Pod (FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Api"
    [ testPropertyNamed "GET /healthz returns 200" "prop_healthz" prop_healthz,
      testPropertyNamed "GET / returns 200 with dashboard HTML" "prop_dashboard" prop_dashboard,
      testPropertyNamed "unknown route returns 405" "prop_unknownRoute" prop_unknownRoute,
      testPropertyNamed "POST /api/v1/pods with valid JSON returns 201" "prop_postPodValid" prop_postPodValid,
      testPropertyNamed "POST /api/v1/pods with invalid JSON returns 400" "prop_postPodInvalid" prop_postPodInvalid,
      testPropertyNamed "GET /api/v1/pods on empty store returns 200" "prop_listPodsEmpty" prop_listPodsEmpty,
      testPropertyNamed "GET /api/v1/pods/<name> not found returns 404" "prop_getPodNotFound" prop_getPodNotFound,
      testPropertyNamed "DELETE /api/v1/pods/<name> not found returns 404" "prop_deletePodNotFound" prop_deletePodNotFound,
      testPropertyNamed "POST /api/v1/nodes with valid JSON returns 201" "prop_postNodeValid" prop_postNodeValid,
      testPropertyNamed "GET /api/v1/nodes on empty store returns 200" "prop_listNodesEmpty" prop_listNodesEmpty,
      testPropertyNamed "GET /api/v1/pods/<name>/logs not found returns 404" "prop_getPodLogsNotFound" prop_getPodLogsNotFound,
      testPropertyNamed "GET /api/v1/pods/<name>/logs unscheduled returns 400" "prop_getPodLogsNotScheduled" prop_getPodLogsNotScheduled,
      testPropertyNamed "GET /api/v1/pods/<name>/logs scheduled returns 200" "prop_getPodLogsScheduled" prop_getPodLogsScheduled
    ]

-- | Run handleRequest through the full pure interpreter stack.
-- Uses a minimal config with just the dashboard HTML file seeded.
runPureApi :: LBS.ByteString -> Request -> Response
runPureApi = runPureApiWith defaultPureConfig

-- | Run handleRequest with a custom pure config, seeding the dashboard file.
runPureApiWith :: App.PureAppConfig -> LBS.ByteString -> Request -> Response
runPureApiWith cfg body req =
  pureResultValue $
    runAppPure
      cfg {App.pureFiles = Map.insert "static/index.html" "<html>test</html>" (App.pureFiles cfg)}
      (handleRequest body req)

-- | Extract status from a WAI Response.
responseStatus :: Response -> Status
responseStatus (ResponseBuilder s _ _) = s
responseStatus (ResponseFile s _ _ _) = s
responseStatus (ResponseStream s _ _) = s
responseStatus (ResponseRaw _ r) = responseStatus r

-- | Build a test request with the given method and path segments.
testRequest :: Method -> [Text] -> Request
testRequest method path = defaultRequest {requestMethod = method, pathInfo = path}

type Method = ByteString

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genPodSpec :: Gen PodSpec
genPodSpec =
  (PodSpec . PodName <$> genText)
    <*> (FlakeRef <$> genText)
    <*> (ResourceRequests <$> Gen.element ["100m", "500m", "1000m"] <*> Gen.element ["128Mi", "256Mi", "512Mi"])
    <*> Gen.int (Range.linear 1 5)

genNode :: Gen Node
genNode =
  (Node . NodeName <$> genText)
    <*> genText

-- | The health endpoint should always succeed, giving load balancers and
-- uptime monitors a reliable signal that the server is alive.
prop_healthz :: Property
prop_healthz = property $ do
  let resp = runPureApi "" (testRequest "GET" ["healthz"])
  responseStatus resp === status200

-- | The root path serves the dashboard HTML. Verify it returns 200 so we
-- know the file server wiring is correct and the index page is reachable.
prop_dashboard :: Property
prop_dashboard = property $ do
  let resp = runPureApi "" (testRequest "GET" [])
  responseStatus resp === status200

-- | Any HTTP method/path combination not handled by the router should get
-- a 405 Method Not Allowed, not a 404 or 500.
prop_unknownRoute :: Property
prop_unknownRoute = property $ do
  path <- forAll $ Gen.list (Range.linear 1 5) genText
  let resp = runPureApi "" (testRequest "PATCH" path)
  responseStatus resp === status405

-- | Submitting a well-formed pod spec should succeed with 201 Created.
-- The spec is randomly generated to ensure the endpoint accepts any valid shape.
prop_postPodValid :: Property
prop_postPodValid = property $ do
  spec <- forAll genPodSpec
  let resp = runPureApi (encode spec) (testRequest "POST" ["api", "v1", "pods"])
  responseStatus resp === status201

-- | Submitting garbage instead of valid JSON should be rejected with 400.
prop_postPodInvalid :: Property
prop_postPodInvalid = property $ do
  let resp = runPureApi "not json" (testRequest "POST" ["api", "v1", "pods"])
  responseStatus resp === status400

-- | Listing pods when the store is empty should still return 200 (with an
-- empty list), not an error.
prop_listPodsEmpty :: Property
prop_listPodsEmpty = property $ do
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "pods"])
  responseStatus resp === status200

-- | Getting a pod by name that doesn't exist should return 404.
prop_getPodNotFound :: Property
prop_getPodNotFound = property $ do
  name <- forAll genText
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "pods", name])
  responseStatus resp === status404

-- | Deleting a pod that doesn't exist should return 404, not silently succeed.
prop_deletePodNotFound :: Property
prop_deletePodNotFound = property $ do
  name <- forAll genText
  let resp = runPureApi "" (testRequest "DELETE" ["api", "v1", "pods", name])
  responseStatus resp === status404

-- | Registering a well-formed node should succeed with 201 Created.
prop_postNodeValid :: Property
prop_postNodeValid = property $ do
  node <- forAll genNode
  let resp = runPureApi (encode node) (testRequest "POST" ["api", "v1", "nodes"])
  responseStatus resp === status201

-- | Listing nodes when the store is empty should return 200 with an empty list.
prop_listNodesEmpty :: Property
prop_listNodesEmpty = property $ do
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "nodes"])
  responseStatus resp === status200

-- | Requesting logs for a pod that doesn't exist should return 404.
prop_getPodLogsNotFound :: Property
prop_getPodLogsNotFound = property $ do
  name <- forAll genText
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "pods", name, "logs"])
  responseStatus resp === status404

-- | Requesting logs for a pod that exists but has no node assignment
-- should return 400 because there's nowhere to stream logs from.
prop_getPodLogsNotScheduled :: Property
prop_getPodLogsNotScheduled = property $ do
  spec <- forAll genPodSpec
  let podN = podName spec
      pod = Pod {podSpec = spec, podState = Pending, podNode = Nothing, podNetwork = Nothing}
      cfg = defaultPureConfig {App.pureStoreState = Map.singleton podN pod}
      resp = runPureApiWith cfg "" (testRequest "GET" ["api", "v1", "pods", podNameText podN, "logs"])
  responseStatus resp === status400

-- | Requesting logs for a scheduled pod with a known node should return 200
-- (a streaming response that will pipe SSH journalctl output).
prop_getPodLogsScheduled :: Property
prop_getPodLogsScheduled = property $ do
  spec <- forAll genPodSpec
  nodeAddr <- forAll genText
  let podN = podName spec
      nodeN = NodeName "test-node"
      node = Node nodeN nodeAddr
      pod = Pod {podSpec = spec, podState = Scheduled, podNode = Just nodeN, podNetwork = Nothing}
      cfg =
        defaultPureConfig
          { App.pureStoreState = Map.singleton podN pod,
            App.pureNodeStoreState = Map.singleton nodeN node
          }
      resp = runPureApiWith cfg "" (testRequest "GET" ["api", "v1", "pods", podNameText podN, "logs"])
  responseStatus resp === status200

podNameText :: PodName -> Text
podNameText (PodName t) = t
