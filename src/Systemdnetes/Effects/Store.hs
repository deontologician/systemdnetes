module Systemdnetes.Effects.Store
  ( Store (..),
    submitPod,
    listPods,
    getPod,
    deletePod,
    updatePodSpec,
    setPodState,
    assignPodNode,
    setPodNetwork,
  )
where

import Polysemy
import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.Pod (NetworkInfo, Pod, PodName, PodSpec, PodState)

data Store m a where
  SubmitPod :: PodSpec -> Store m ()
  ListPods :: Store m [Pod]
  GetPod :: PodName -> Store m (Maybe Pod)
  DeletePod :: PodName -> Store m ()
  UpdatePodSpec :: PodName -> PodSpec -> Store m ()
  SetPodState :: PodName -> PodState -> Store m ()
  AssignPodNode :: PodName -> NodeName -> Store m ()
  SetPodNetwork :: PodName -> NetworkInfo -> Store m ()

makeSem ''Store
