
import Test.Framework (defaultMain, testGroup, Test(..))
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck (Gen(..), elements, choose, vectorOf, label, conjoin)

import Crypto.Nettle.Ciphers
import Crypto.Cipher.Types

import qualified Data.ByteString as B
import Data.Word (Word8)
import qualified Numeric as N
import Data.Maybe (fromJust)

fromRight :: Either a b -> b
fromRight (Right x) = x
fromRight _ = error "expected Right"

genByteString :: Int -> Gen B.ByteString
genByteString len = vectorOf len (choose (0,255)) >>= return . B.pack

runEither :: (Monad m, Show e) => Either e x -> m x
runEither (Left e) = fail $ show e
runEither (Right x) = return x

runMaybe :: (Monad m) => Maybe x -> m x
runMaybe Nothing = fail $ "got nothing"
runMaybe (Just x) = return x

genKey' :: KeySizeSpecifier -> Gen B.ByteString
genKey' spec = case spec of
	KeySizeRange bot top -> choose (bot, top) >>= genByteString
	KeySizeEnum list     -> elements list >>= genByteString
	KeySizeFixed f       -> genByteString f

genKey :: Cipher c => c -> Gen (Key c)
genKey c = genKey' (cipherKeySize c) >>= runEither . makeKey

genCipher :: Cipher c => c -> Gen c
genCipher c = genKey c >>= return . cipherInit

genIV :: BlockCipher c => c -> Gen (IV c)
genIV c = genByteString (blockSize c) >>= runMaybe . makeIV

genBlockCipherInput :: BlockCipher c => c -> Int -> Gen (B.ByteString)
genBlockCipherInput c blocks = genByteString (blockSize c * blocks)

genBlockTest :: BlockCipher c => c -> Test
genBlockTest = genBlockTest' . genCipher

genBlockTest' :: BlockCipher c => Gen c -> Test
genBlockTest' = go undefined where
	go :: BlockCipher c => c -> Gen c -> Test
	go c' genci = testProperty ("generated " ++ cipherName c' ++ " block cipher test") $ do
		c <- genci
		iv <- genIV c
		block1 <- genBlockCipherInput c 1
		block10 <- genBlockCipherInput c 10
		input <- choose (1, B.length block10) >>= genByteString
		return $ conjoin $
			[ label "ecbEncrypt + ecbDecrypt 1 block"   $ (ecbDecrypt c    . ecbEncrypt c   ) block1  == block1
			, label "ecbDecrypt + ecbEncrypt 1 block"   $ (ecbEncrypt c    . ecbDecrypt c   ) block1  == block1
			, label "ecbEncrypt + ecbDecrypt 10 blocks" $ (ecbDecrypt c    . ecbEncrypt c   ) block10 == block10
			, label "ecbDecrypt + ecbEncrypt 10 blocks" $ (ecbEncrypt c    . ecbDecrypt c   ) block10 == block10
			, label "cbcEncrypt + cbcDecrypt 1 block"   $ (cbcDecrypt c iv . cbcEncrypt c iv) block1  == block1
			, label "cbcDecrypt + cbcEncrypt 1 block"   $ (cbcEncrypt c iv . cbcDecrypt c iv) block1  == block1
			, label "cbcEncrypt + cbcDecrypt 10 blocks" $ (cbcDecrypt c iv . cbcEncrypt c iv) block10 == block10
			, label "cbcDecrypt + cbcEncrypt 10 blocks" $ (cbcEncrypt c iv . cbcDecrypt c iv) block10 == block10
			, label "cfbEncrypt + cfbDecrypt 1 block"   $ (cfbDecrypt c iv . cfbEncrypt c iv) block1  == block1
			, label "cfbDecrypt + cfbEncrypt 1 block"   $ (cfbEncrypt c iv . cfbDecrypt c iv) block1  == block1
			, label "cfbEncrypt + cfbDecrypt 10 blocks" $ (cfbDecrypt c iv . cfbEncrypt c iv) block10 == block10
			, label "cfbDecrypt + cfbEncrypt 10 blocks" $ (cfbEncrypt c iv . cfbDecrypt c iv) block10 == block10
			, label "ctrCombine + ctrCombine 1 block"   $ (ctrCombine c iv . ctrCombine c iv) block1  == block1
			, label "ctrCombine + ctrCombine 10 blocks" $ (ctrCombine c iv . ctrCombine c iv) block10 == block10
			, label "ctrCombine + ctrCombine unaligned" $ (ctrCombine c iv . ctrCombine c iv) input   == input
			]

genStreamTest :: StreamCipher c => c -> Test
genStreamTest c' = testProperty ("generated " ++ cipherName c' ++ " stream cipher test") $ do
	c <- genCipher c'
	let run i = fst $ streamCombine c i
	let run2 (i1, i2) = fst $ let (o1, c') = streamCombine c i1; (o2, c'') = streamCombine c' i2 in (B.append o1 o2, c'')
	input1 <- choose (1, 256) >>= genByteString
	input2 <- choose (1, 256) >>= genByteString
	return $ conjoin $
		[ label "streamCombine one block" $ run (run input1) == input1
		, label "streamCombine two blocks" $ run (run2 (input1, input2)) == B.append input1 input2
		]

genStreamNonceTest :: StreamNonceCipher c => c -> Test
genStreamNonceTest c' = testProperty ("generated " ++ cipherName c' ++ " stream cipher with nonce test") $ do
	c'' <- genCipher c'
	nonce <- genKey' (streamNonceSize c')
	let Just c = streamSetNonce c'' nonce
	let run i = fst $ streamCombine c i
	let run2 (i1, i2) = fst $ let (o1, c') = streamCombine c i1; (o2, c'') = streamCombine c' i2 in (B.append o1 o2, c'')
	input1 <- choose (1, 256) >>= genByteString
	input2 <- choose (1, 256) >>= genByteString
	return $ conjoin $
		[ label "streamCombine one block with nonce" $ run (run input1) == input1
		, label "streamCombine two blocks with nonce" $ run (run2 (input1, input2)) == B.append input1 input2
		]

genStreamNonceWord64Test :: StreamNonceCipher c => c -> Test
genStreamNonceWord64Test c' = testProperty ("generated " ++ cipherName c' ++ " stream cipher with word64 nonce test") $ do
	c'' <- genCipher c'
	nonce <- choose (minBound,maxBound)
	let Just c = streamSetNonceWord64 c'' nonce
	let run i = fst $ streamCombine c i
	let run2 (i1, i2) = fst $ let (o1, c') = streamCombine c i1; (o2, c'') = streamCombine c' i2 in (B.append o1 o2, c'')
	input1 <- choose (1, 256) >>= genByteString
	input2 <- choose (1, 256) >>= genByteString
	return $ conjoin $
		[ label "streamCombine one block with nonce" $ run (run input1) == input1
		, label "streamCombine two blocks with nonce" $ run (run2 (input1, input2)) == B.append input1 input2
		]

gen_arctwoInitEKB :: Gen ARCTWO
gen_arctwoInitEKB = do
	k <- genKey (undefined :: ARCTWO)
	ekb <- choose (0, 1024)
	return $ arctwoInitEKB k ekb

gen_arctwoInitGutmann :: Gen ARCTWO
gen_arctwoInitGutmann = do
	k <- genKey (undefined :: ARCTWO)
	return $ arctwoInitGutmann k

main = defaultMain
-- these checks just make sure the api isn't broken horribly
	[ genBlockTest (undefined :: AES)
	, genBlockTest (undefined :: AES128)
	, genBlockTest (undefined :: AES192)
	, genBlockTest (undefined :: AES256)
	, genBlockTest (undefined :: ARCTWO)
	, genBlockTest' gen_arctwoInitEKB
	, genBlockTest' gen_arctwoInitGutmann
	, genBlockTest (undefined :: BLOWFISH)
	, genBlockTest (undefined :: Camellia)
	, genBlockTest (undefined :: Camellia128)
	, genBlockTest (undefined :: Camellia192)
	, genBlockTest (undefined :: Camellia256)
	, genBlockTest (undefined :: CAST128)
	, genBlockTest (undefined :: DES)
	, genBlockTest (undefined :: DES_EDE3)
	, genBlockTest (undefined :: TWOFISH)
	, genBlockTest (undefined :: SERPENT)
	, genStreamTest (undefined :: ARCFOUR)
	, genStreamTest (undefined :: SALSA20)
	, genStreamTest (undefined :: ESTREAM_SALSA20)
	, genStreamNonceTest (undefined :: SALSA20)
	, genStreamNonceTest (undefined :: ESTREAM_SALSA20)
	, genStreamNonceWord64Test (undefined :: SALSA20)
	, genStreamNonceWord64Test (undefined :: ESTREAM_SALSA20)
	]
