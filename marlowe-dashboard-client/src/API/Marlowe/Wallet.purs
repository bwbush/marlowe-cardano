module API.Marlowe.Run.Wallet
  ( getTotalFunds
  ) where

import Prologue
import API.Request (doGetRequest)
import API.Url (toUrlPiece)
import Component.Contacts.Types (WalletId)
import Control.Monad.Error.Class (class MonadError)
import Effect.Aff.Class (class MonadAff)
import Marlowe.Run.Wallet.V1 (GetTotalFundsResponse) as BE
import Servant.PureScript (AjaxError)

getTotalFunds
  :: forall m
   . MonadAff m
  => MonadError AjaxError m
  => WalletId
  -> m BE.GetTotalFundsResponse
getTotalFunds wallet =
  doGetRequest
    $ "/api/wallet/v1/"
        <> toUrlPiece wallet
        <> "/total-funds"
