{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}

module Network.Protocol.ChainSeek.Codec
  ( DeserializeError
  , codecChainSeek
  ) where

import Data.Binary
import qualified Data.ByteString.Lazy as LBS
import Data.Type.Equality (type (:~:)(Refl))
import Network.Protocol.ChainSeek.Types
import Network.Protocol.Codec (DeserializeError, GetMessage, PutMessage, binaryCodec)
import Network.TypedProtocol.Codec

codecChainSeek
  :: forall query point tip m
   . ( Applicative m
     , Query query
     , Binary point
     , Binary tip
     )
  => Codec (ChainSeek query point tip) DeserializeError m LBS.ByteString
codecChainSeek = binaryCodec putMsg getMsg
  where
    putMsg :: PutMessage (ChainSeek query point tip)
    putMsg (ClientAgency TokInit) msg = case msg of
      MsgRequestHandshake schemaVersion -> do
        putWord8 0x01
        put schemaVersion

    putMsg (ClientAgency TokIdle) msg = case msg of
      MsgQueryNext query -> do
        putWord8 0x04
        let tag = tagFromQuery query
        putTag tag
        putQuery query
      MsgDone            -> putWord8 0x09

    putMsg (ServerAgency TokHandshake) msg = case msg of
      MsgConfirmHandshake                  -> putWord8 0x02
      MsgRejectHandshake supportedVersions -> do
       putWord8 0x03
       put supportedVersions

    putMsg (ServerAgency (TokNext tag)) (MsgRejectQuery err tip) = do
        putWord8 0x05
        putTag tag
        putErr tag err
        put tip

    putMsg (ServerAgency (TokNext tag)) (MsgRollForward result pos tip) = do
        putWord8 0x06
        putTag tag
        putResult tag result
        put pos
        put tip

    putMsg (ServerAgency TokNext{}) (MsgRollBackward pos tip) = do
        putWord8 0x07
        put pos
        put tip

    putMsg (ServerAgency TokNext{}) MsgWait = putWord8 0x08

    putMsg (ClientAgency TokPoll) MsgPoll = putWord8 0x0a

    putMsg (ClientAgency TokPoll) MsgCancel = putWord8 0x0b

    getMsg :: GetMessage (ChainSeek query point tip)
    getMsg tok      = do
      tag <- getWord8
      case (tag, tok) of
        (0x01, ClientAgency TokInit) -> SomeMessage . MsgRequestHandshake <$> get

        (0x04, ClientAgency TokIdle) -> do
          SomeTag qtag <- getTag
          SomeMessage . MsgQueryNext <$> getQuery qtag

        (0x09, ClientAgency TokIdle) -> pure $ SomeMessage MsgDone

        (0x02, ServerAgency TokHandshake) -> pure $ SomeMessage MsgConfirmHandshake

        (0x03, ServerAgency TokHandshake) -> SomeMessage . MsgRejectHandshake <$> get

        (0x05, ServerAgency (TokNext qtag)) -> do
          SomeTag qtag' :: SomeTag query <- getTag
          case tagEq qtag qtag' of
            Nothing -> fail "decoded query tag does not match expected query tag"
            Just (Refl, Refl) -> do
              err <- getErr qtag'
              tip <- get
              pure $ SomeMessage $ MsgRejectQuery err tip

        (0x06, ServerAgency (TokNext qtag)) -> do
          SomeTag qtag' :: SomeTag query <- getTag
          case tagEq qtag qtag' of
            Nothing -> fail "decoded query tag does not match expected query tag"
            Just (Refl, Refl) -> do
              result <- getResult qtag'
              point <- get
              tip <- get
              pure $ SomeMessage $ MsgRollForward result point tip

        (0x07, ServerAgency (TokNext _)) -> do
          point <- get
          tip <- get
          pure $ SomeMessage $ MsgRollBackward point tip

        (0x08, ServerAgency (TokNext _)) -> pure $ SomeMessage MsgWait

        (0x0a, ClientAgency TokPoll) -> pure $ SomeMessage MsgPoll

        (0x0b, ClientAgency TokPoll) -> pure $ SomeMessage MsgCancel

        _ -> fail $ "Unexpected tag " <> show tag
