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
import Polysemy
import Systemdnetes.Api (handleRequest)
import Systemdnetes.Domain.Node (Node (..), NodeName (..))
import Systemdnetes.Domain.Pod (FlakeRef (..), PodName (..), PodSpec (..), ResourceRequests (..))
import Systemdnetes.Effects.FileServer.Interpreter (fileServerToPure)
import Systemdnetes.Effects.Log.Interpreter (logToList)
import Systemdnetes.Effects.NodeStore.Interpreter (nodeStoreToPure)
import Systemdnetes.Effects.Ssh.Interpreter (sshToPure)
import Systemdnetes.Effects.Store.Interpreter (storeToPure)
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
      testPropertyNamed "GET /api/v1/nodes on empty store returns 200" "prop_listNodesEmpty" prop_listNodesEmpty
    ]

-- | Run handleRequest through the full pure interpreter stack.
runPureApi :: LBS.ByteString -> Request -> Response
runPureApi body req =
  snd . snd . snd $
    run $
      fileServerToPure (Map.singleton "static/index.html" "<html>test</html>") $
        sshToPure Map.empty $
          nodeStoreToPure Map.empty $
            storeToPure Map.empty $
              logToList $
                handleRequest body req

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

prop_healthz :: Property
prop_healthz = property $ do
  let resp = runPureApi "" (testRequest "GET" ["healthz"])
  responseStatus resp === status200

prop_dashboard :: Property
prop_dashboard = property $ do
  let resp = runPureApi "" (testRequest "GET" [])
  responseStatus resp === status200

prop_unknownRoute :: Property
prop_unknownRoute = property $ do
  path <- forAll $ Gen.list (Range.linear 1 5) genText
  let resp = runPureApi "" (testRequest "PATCH" path)
  responseStatus resp === status405

prop_postPodValid :: Property
prop_postPodValid = property $ do
  spec <- forAll genPodSpec
  let resp = runPureApi (encode spec) (testRequest "POST" ["api", "v1", "pods"])
  responseStatus resp === status201

prop_postPodInvalid :: Property
prop_postPodInvalid = property $ do
  let resp = runPureApi "not json" (testRequest "POST" ["api", "v1", "pods"])
  responseStatus resp === status400

prop_listPodsEmpty :: Property
prop_listPodsEmpty = property $ do
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "pods"])
  responseStatus resp === status200

prop_getPodNotFound :: Property
prop_getPodNotFound = property $ do
  name <- forAll genText
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "pods", name])
  responseStatus resp === status404

prop_deletePodNotFound :: Property
prop_deletePodNotFound = property $ do
  name <- forAll genText
  let resp = runPureApi "" (testRequest "DELETE" ["api", "v1", "pods", name])
  responseStatus resp === status404

prop_postNodeValid :: Property
prop_postNodeValid = property $ do
  node <- forAll genNode
  let resp = runPureApi (encode node) (testRequest "POST" ["api", "v1", "nodes"])
  responseStatus resp === status201

prop_listNodesEmpty :: Property
prop_listNodesEmpty = property $ do
  let resp = runPureApi "" (testRequest "GET" ["api", "v1", "nodes"])
  responseStatus resp === status200
