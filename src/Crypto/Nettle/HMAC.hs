-----------------------------------------------------------------------------
-- |
-- Module      :  Crypto.Nettle.HMAC
-- Copyright   :  (c) 2013 Stefan Bühler
-- License     :  MIT-style (see the file COPYING)
-- 
-- Maintainer  :  stbuehler@web.de
-- Stability   :  experimental
-- Portability :  portable
--
-- Generic HMAC implementation based on the 'HashAlgorithm' class,
-- implementing the 'KeyedHashAlgorithm' class.
--
-----------------------------------------------------------------------------

module Crypto.Nettle.HMAC
	( HMAC
	, HMACState
	, hmacInit
	, hmacInit'
	, hmac
	, hmac'
	) where

import Crypto.Nettle.Hash.Types