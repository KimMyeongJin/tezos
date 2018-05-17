(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

(** Tezos - X25519/XSalsa20-Poly1305 cryptography *)

open Tweetnacl

type secret_key = Box.secret Box.key
type public_key = Box.public Box.key
type channel_key = Box.combined Box.key
type nonce = Nonce.t
type target = Z.t

module Secretbox = struct
  include Secretbox

  let box key msg nonce = box ~key ~msg ~nonce

  let box_open key cmsg nonce = box_open ~key ~cmsg ~nonce

  let box_noalloc key nonce msg =
    box_noalloc ~key ~nonce ~msg

  let box_open_noalloc key nonce cmsg =
    box_open_noalloc ~key ~nonce ~cmsg
end

module Public_key_hash = Blake2B.Make (Base58) (struct
    let name = "Crypto_box.Public_key_hash"
    let title = "A Cryptobox public key ID"
    let b58check_prefix = Base58.Prefix.cryptobox_public_key_hash
    let size = Some 16
  end)

let () =
  Base58.check_encoded_prefix Public_key_hash.b58check_encoding "id" 30

let hash pk =
  Public_key_hash.hash_bytes [Box.to_bytes pk]

let zerobytes = Box.zerobytes
let boxzerobytes = Box.boxzerobytes

let random_keypair () =
  let pk, sk = Box.keypair () in
  sk, pk, hash pk

let zero_nonce = Tweetnacl.Nonce.(of_bytes_exn (MBytes.make bytes '\x00'))
let random_nonce = Nonce.gen
let increment_nonce = Nonce.increment

let box sk pk msg nonce = Box.box ~sk ~pk ~msg ~nonce

let box_open sk pk cmsg nonce = Box.box_open ~sk ~pk ~cmsg ~nonce

let box_noalloc sk pk nonce msg =
  Box.box_noalloc ~sk ~pk ~nonce ~msg

let box_open_noalloc sk pk nonce cmsg =
  Box.box_open_noalloc ~sk ~pk ~nonce ~cmsg

let precompute sk pk = Box.combine pk sk

let fast_box k msg nonce =
  Box.box_combined ~k ~msg ~nonce

let fast_box_open k cmsg nonce =
  Box.box_open_combined ~k ~cmsg ~nonce

let fast_box_noalloc k nonce msg =
  Box.box_combined_noalloc ~k ~nonce ~msg

let fast_box_open_noalloc k nonce cmsg =
  Box.box_open_combined_noalloc ~k ~nonce ~cmsg

let compare_target hash target =
  let hash = Z.of_bits (Blake2B.to_string hash) in
  Z.compare hash target <= 0

let make_target f =
  if f < 0. || 256. < f then invalid_arg "Cryptobox.target_of_float" ;
  let frac, shift = modf f in
  let shift = int_of_float shift in
  let m =
    Z.of_int64 @@
    if frac = 0. then
      Int64.(pred (shift_left 1L 54))
    else
      Int64.of_float (2. ** (54. -. frac))
  in
  if shift < 202 then
    Z.logor
      (Z.shift_left m (202 - shift))
      (Z.pred @@ Z.shift_left Z.one (202 - shift))
  else
    Z.shift_right m (shift - 202)

let default_target = make_target 24.

let check_proof_of_work pk nonce target =
  let hash =
    Blake2B.hash_bytes [
      Box.to_bytes pk ;
      Nonce.to_bytes nonce ;
    ] in
  compare_target hash target

let generate_proof_of_work ?max pk target =
  let may_interupt =
    match max with
    | None -> (fun _ -> ())
    | Some max -> (fun cpt -> if max < cpt then raise Not_found) in
  let rec loop nonce cpt =
    may_interupt cpt ;
    if check_proof_of_work pk nonce target then
      nonce
    else
      loop (Nonce.increment nonce) (cpt + 1) in
  loop (random_nonce ()) 0

let public_key_to_bigarray = Box.to_bytes
let public_key_of_bigarray = Box.pk_of_bytes_exn
let public_key_size = Box.pkbytes

let secret_key_to_bigarray = Box.to_bytes
let secret_key_of_bigarray = Box.sk_of_bytes_exn
let secret_key_size = Box.skbytes

let nonce_to_bigarray = Nonce.to_bytes
let nonce_of_bigarray = Nonce.of_bytes_exn
let nonce_size = Nonce.bytes

let public_key_encoding =
  let open Data_encoding in
  conv
    public_key_to_bigarray
    public_key_of_bigarray
    (Fixed.bytes public_key_size)

let secret_key_encoding =
  let open Data_encoding in
  conv
    secret_key_to_bigarray
    secret_key_of_bigarray
    (Fixed.bytes secret_key_size)

let nonce_encoding =
  let open Data_encoding in
  conv
    nonce_to_bigarray
    nonce_of_bigarray
    (Fixed.bytes nonce_size)

