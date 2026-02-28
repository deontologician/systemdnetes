module Systemdnetes.Effects.Store
  ( Store (..),
    submitPod,
    listPods,
    getPod,
    deletePod,
  )
where

import Polysemy
import Systemdnetes.Domain.Pod (Pod, PodName, PodSpec)

data Store m a where
  SubmitPod :: PodSpec -> Store m ()
  ListPods :: Store m [Pod]
  GetPod :: PodName -> Store m (Maybe Pod)
  DeletePod :: PodName -> Store m ()

makeSem ''Store
