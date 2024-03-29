{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | The type of the job protocol.
--
-- The job protocol is used to execute commands as jobs. Job status can be
-- polled by the client while it is running. A client can also attach to a
-- running job and poll its status. When a job completes, it must either report
-- a success or failure.

module Network.Protocol.Job.Types
  where

import Data.Aeson (Value(..), object, (.=))
import Data.Binary (Put)
import Data.Binary.Get (Get)
import Data.Functor ((<&>))
import Data.Maybe (catMaybes)
import Data.Proxy (Proxy(..))
import qualified Data.Text as T
import Data.Type.Equality (type (:~:)(Refl))
import GHC.Show (showSpace)
import Network.Protocol.Codec.Spec (ArbitraryMessage(..), MessageEq(..), ShowProtocol(..))
import Network.Protocol.Driver (MessageToJSON(..))
import Network.Protocol.Handshake.Types (HasSignature(..))
import Network.TypedProtocol
import Network.TypedProtocol.Codec (AnyMessageAndAgency(..))
import Test.QuickCheck (Gen, oneof)

data SomeTag cmd = forall status err result. SomeTag (Tag cmd status err result)

-- | A class for commands. Defines associated types and conversion
-- functions needed to run the protocol.
class Command (cmd :: * -> * -> * -> *) where

  -- | The type of job IDs for this command type.
  data JobId cmd :: * -> * -> * -> *

  -- | The type of tags for this command type. Used exclusively for GADT
  -- pattern matching.
  data Tag cmd :: * -> * -> * -> *

  -- | Obtain a token from a command.
  tagFromCommand :: cmd status err result -> Tag cmd status err result

  -- | Obtain a token from a command ID.
  tagFromJobId :: JobId cmd status err result -> Tag cmd status err result

  -- | Prove that two tags are the same.
  tagEq :: Tag cmd status err result -> Tag cmd status' err' result' -> Maybe (status :~: status', err :~: err', result :~: result')

  putTag :: Tag cmd status err result -> Put
  getTag :: Get (SomeTag cmd)
  putJobId :: JobId cmd status err result -> Put
  getJobId :: Tag cmd status err result -> Get (JobId cmd status err result)
  putCommand :: cmd status err result -> Put
  getCommand :: Tag cmd status err result -> Get (cmd status err result)
  putStatus :: Tag cmd status err result -> status -> Put
  getStatus :: Tag cmd status err result -> Get status
  putErr :: Tag cmd status err result -> err -> Put
  getErr :: Tag cmd status err result -> Get err
  putResult :: Tag cmd status err result -> result -> Put
  getResult :: Tag cmd status err result -> Get result

class Command cmd => CommandToJSON cmd where
  commandToJSON :: cmd status err result -> Value
  jobIdToJSON :: JobId cmd status err result -> Value
  errToJSON :: Tag cmd status err result -> err -> Value
  resultToJSON :: Tag cmd status err result -> result -> Value
  statusToJSON :: Tag cmd status err result -> status -> Value

-- | A state kind for the job protocol.
data Job (cmd :: * -> * -> * -> *) where

  -- | The initial state of the protocol.
  StInit :: Job cmd

  -- | In the 'StCmd' state, the server has agency. It is running a command
  -- sent by the client and starting the job.
  StCmd :: status -> err -> result -> Job cmd

  -- | In the 'StAttach' state, the server has agency. It is looking up the job
  -- associated with the given job ID.
  StAttach :: status -> err -> result -> Job cmd

  -- | In the 'StAwait state, the client has agency. It has been previously
  -- told to await a job execution and can either poll the status or detach.
  StAwait :: status -> err -> result -> Job cmd

  -- | The terminal state of the protocol.
  StDone :: Job cmd

instance HasSignature cmd => HasSignature (Job cmd) where
  signature _ = T.intercalate " " ["Job", signature $ Proxy @cmd]

instance Protocol (Job cmd) where

  -- | The type of messages in the protocol. Corresponds to state transition in
  -- the state machine diagram of the protocol.
  data Message (Job cmd) from to where

    -- | Tell the server to execute a command in a new job.
    MsgExec :: cmd status err result -> Message (Job cmd)
      'StInit
      ('StCmd status err result)

    -- | Attach to the job of previously executed command.
    MsgAttach :: JobId cmd status err result -> Message (Job cmd)
      'StInit
      ('StAttach status err result)

    -- | Attaching to the job succeeded.
    MsgAttached :: Message (Job cmd)
      ('StAttach status err result)
      ('StCmd status err result)

    -- | Attaching to the job failed.
    MsgAttachFailed :: Message (Job cmd)
      ('StAttach status err result)
      'StDone

    -- | Tell the client the job failed.
    MsgFail :: err -> Message (Job cmd)
      ('StCmd status err result)
      'StDone

    -- | Tell the client the job succeeded.
    MsgSucceed :: result -> Message (Job cmd)
      ('StCmd status err result)
      'StDone

    -- | Tell the client the job is in progress.
    MsgAwait :: status -> JobId cmd status err result -> Message (Job cmd)
      ('StCmd status err result)
      ('StAwait status err result)

    -- | Ask the server for the current status of the job.
    MsgPoll :: Message (Job cmd)
      ('StAwait status err result)
      ('StCmd status err result)

    -- | Detach from the session and close the protocol.
    MsgDetach :: Message (Job cmd)
      ('StAwait status err result)
      'StDone

  data ClientHasAgency st where
    TokInit :: ClientHasAgency 'StInit
    TokAwait :: Tag cmd status err result -> ClientHasAgency ('StAwait status err result :: Job cmd)

  data ServerHasAgency st where
    TokCmd :: Tag cmd status err result -> ServerHasAgency ('StCmd status err result :: Job cmd)
    TokAttach :: Tag cmd status err result -> ServerHasAgency ('StAttach status err result :: Job cmd)

  data NobodyHasAgency st where
    TokDone :: NobodyHasAgency 'StDone

  exclusionLemma_ClientAndServerHaveAgency TokInit      = \case
  exclusionLemma_ClientAndServerHaveAgency (TokAwait _) = \case

  exclusionLemma_NobodyAndClientHaveAgency TokDone = \case

  exclusionLemma_NobodyAndServerHaveAgency TokDone = \case

instance CommandToJSON cmd => MessageToJSON (Job cmd) where
  messageToJSON = \case
    ClientAgency TokInit -> \case
      MsgExec cmd -> object [ "exec" .= commandToJSON cmd ]
      MsgAttach jobId -> object [ "attach" .= jobIdToJSON jobId ]
    ClientAgency (TokAwait _) -> String . \case
      MsgPoll -> "poll"
      MsgDetach -> "detach"
    ServerAgency (TokCmd tag)-> \case
      MsgFail err -> object [ "fail" .= errToJSON tag err ]
      MsgSucceed result -> object [ "succeed" .= resultToJSON tag result ]
      MsgAwait status jobId -> object
        [ "await" .= object
            [ "status" .= statusToJSON tag status
            , "jobId" .= jobIdToJSON jobId
            ]
        ]
    ServerAgency (TokAttach _) -> String . \case
      MsgAttached -> "attached"
      MsgAttachFailed -> "attachFailed"

class Command cmd => ArbitraryCommand cmd where
  arbitraryTag :: Gen (SomeTag cmd)
  arbitraryCmd :: Tag cmd status err result -> Gen (cmd status err result)
  arbitraryJobId :: Tag cmd status err result -> Maybe (Gen (JobId cmd status err result))
  arbitraryStatus :: Tag cmd status err result -> Maybe (Gen status)
  arbitraryErr :: Tag cmd status err result -> Maybe (Gen err)
  arbitraryResult :: Tag cmd status err result -> Gen result
  shrinkCommand :: cmd status err result -> [cmd status err result]
  shrinkJobId :: JobId cmd status err result -> [JobId cmd status err result]
  shrinkErr :: Tag cmd status err result -> err -> [err]
  shrinkResult :: Tag cmd status err result -> result -> [result]
  shrinkStatus :: Tag cmd status err result -> status -> [status]

instance ArbitraryCommand cmd => ArbitraryMessage (Job cmd) where
  arbitraryMessage = do
    SomeTag tag <- arbitraryTag
    let mError = arbitraryErr tag
    let mStatus = arbitraryStatus tag
    let mJobId = arbitraryJobId tag
    oneof $ catMaybes
      [ Just $ AnyMessageAndAgency (ClientAgency TokInit) . MsgExec <$> arbitraryCmd tag
      , mJobId <&> \genJobId -> do
          jobId <- genJobId
          pure $ AnyMessageAndAgency (ClientAgency TokInit) $ MsgAttach jobId
      , Just $ pure $ AnyMessageAndAgency (ServerAgency (TokAttach tag)) MsgAttached
      , Just $ pure $ AnyMessageAndAgency (ServerAgency (TokAttach tag)) MsgAttachFailed
      , mError <&> \genErr -> do
          err <- genErr
          pure $ AnyMessageAndAgency (ServerAgency $ TokCmd tag) $ MsgFail err
      , Just $ AnyMessageAndAgency (ServerAgency $ TokCmd tag) . MsgSucceed <$> arbitraryResult tag
      , ((,) <$> mStatus <*> mJobId) <&> \(genStatus, genJobId) -> do
          status <- genStatus
          jobId <- genJobId
          pure $ AnyMessageAndAgency (ServerAgency $ TokCmd tag) $ MsgAwait status jobId
      , Just $ pure $ AnyMessageAndAgency (ClientAgency (TokAwait tag)) MsgPoll
      , Just $ pure $ AnyMessageAndAgency (ClientAgency (TokAwait tag)) MsgDetach
      ]
  shrinkMessage agency = \case
    MsgExec cmd -> MsgExec <$> shrinkCommand cmd
    MsgAttach jobId -> MsgAttach <$> shrinkJobId jobId
    MsgFail err -> MsgFail <$> case agency of ServerAgency (TokCmd tag) -> shrinkErr tag err
    MsgSucceed result -> MsgSucceed <$> case agency of ServerAgency (TokCmd tag) -> shrinkResult tag result
    MsgAwait status jobId -> []
      <> [ MsgAwait status' jobId | status' <- case agency of ServerAgency (TokCmd tag) -> shrinkStatus tag status ]
      <> [ MsgAwait status jobId' | jobId' <- shrinkJobId jobId ]
    _ -> []

class Command cmd => CommandEq cmd where
  commandEq :: cmd status err result -> cmd status err result -> Bool
  jobIdEq :: JobId cmd status err result -> JobId cmd status err result -> Bool
  statusEq :: Tag cmd status err result -> status -> status -> Bool
  errEq :: Tag cmd status err result -> err -> err -> Bool
  resultEq :: Tag cmd status err result -> result -> result -> Bool

instance CommandEq cmd => MessageEq (Job cmd) where
  messageEq (AnyMessageAndAgency agency msg) = case (agency, msg) of
    (_, MsgExec cmd) -> \case
      AnyMessageAndAgency _ (MsgExec cmd') ->
        case tagEq (tagFromCommand cmd) (tagFromCommand cmd') of
          Just (Refl, Refl, Refl) -> commandEq cmd cmd'
          Nothing -> False
      _ -> False
    (_, MsgAttach jobId) -> \case
      AnyMessageAndAgency _ (MsgAttach jobId') ->
        case tagEq (tagFromJobId jobId) (tagFromJobId jobId') of
          Just (Refl, Refl, Refl) -> jobIdEq jobId jobId'
          Nothing -> False
      _ -> False
    (_, MsgAttached) -> \case
      AnyMessageAndAgency _ MsgAttached -> True
      _ -> False
    (_, MsgAttachFailed) -> \case
      AnyMessageAndAgency _ MsgAttachFailed -> True
      _ -> False
    (ServerAgency (TokCmd tag), MsgFail err) -> \case
      AnyMessageAndAgency (ServerAgency (TokCmd tag')) (MsgFail err') ->
        case tagEq tag tag' of
          Just (Refl, Refl, Refl) -> errEq tag err err'
          Nothing -> False
      _ -> False
    (ServerAgency (TokCmd tag), MsgSucceed result) -> \case
      AnyMessageAndAgency (ServerAgency (TokCmd tag')) (MsgSucceed result') ->
        case tagEq tag tag' of
          Just (Refl, Refl, Refl) -> resultEq tag result result'
          Nothing -> False
      _ -> False
    (ServerAgency (TokCmd tag), MsgAwait status jobId) -> \case
      AnyMessageAndAgency (ServerAgency (TokCmd tag')) (MsgAwait status' jobId') ->
        case tagEq tag tag' of
          Just (Refl, Refl, Refl) -> statusEq tag status status' && jobIdEq jobId jobId'
          Nothing -> False
      _ -> False
    (_, MsgPoll) -> \case
      AnyMessageAndAgency _ MsgPoll -> True
      _ -> False
    (_, MsgDetach) -> \case
      AnyMessageAndAgency _ MsgDetach -> True
      _ -> False

class Command cmd => ShowCommand cmd where
  showsPrecTag :: Int -> Tag cmd status err result -> ShowS
  showsPrecCommand :: Int -> cmd status err result -> ShowS
  showsPrecJobId :: Int -> JobId cmd status err result -> ShowS
  showsPrecStatus :: Int -> Tag cmd status err result -> status -> ShowS
  showsPrecErr :: Int -> Tag cmd status err result -> err -> ShowS
  showsPrecResult :: Int -> Tag cmd status err result -> result -> ShowS

instance ShowCommand cmd => ShowProtocol (Job cmd) where
  showsPrecMessage p agency = \case
    MsgExec cmd -> showParen (p >= 11)
      ( showString "MsgExec"
      . showSpace
      . showsPrecCommand 11 cmd
      )
    MsgAttach jobId -> showParen (p >= 11)
      ( showString "MsgAttach"
      . showSpace
      . showsPrecJobId 11 jobId
      )
    MsgAttached -> showString "MsgAttached"
    MsgAttachFailed -> showString "MsgAttachFailed"
    MsgFail err -> showParen (p >= 11)
      ( showString "MsgFail"
      . showSpace
      . case agency of ServerAgency (TokCmd tag) -> showsPrecErr 11 tag err
      )
    MsgSucceed result -> showParen (p >= 11)
      ( showString "MsgSucceed"
      . showSpace
      . case agency of ServerAgency (TokCmd tag) -> showsPrecResult 11 tag result
      )
    MsgAwait status jobId -> showParen (p >= 11)
      ( showString "MsgAwait"
      . showSpace
      . case agency of ServerAgency (TokCmd tag) -> showsPrecStatus 11 tag status
      . showSpace
      . showsPrecJobId 11 jobId
      )
    MsgPoll -> showString "MsgPoll"
    MsgDetach -> showString "MsgDetach"

  showsPrecServerHasAgency p = \case
    TokCmd tag -> showParen (p >= 11)
      ( showString "TokCmd"
      . showSpace
      . showsPrecTag p tag
      )
    TokAttach tag -> showParen (p >= 11)
      ( showString "TokAttach"
      . showSpace
      . showsPrecTag p tag
      )

  showsPrecClientHasAgency p = \case
    TokInit -> showString "TokInit"
    TokAwait tag -> showParen (p >= 11)
      ( showString "TokAwait"
      . showSpace
      . showsPrecTag p tag
      )
