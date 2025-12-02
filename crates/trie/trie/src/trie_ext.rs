use crate::{
    hashed_cursor::{HashedCursor, HashedCursorFactory},
};
use alloy_consensus::constants::KECCAK_EMPTY;
use alloy_primitives::B256;
use alloy_trie::{EMPTY_ROOT_HASH};
use nybbles::Nibbles;
use reth_execution_errors::StateRootError;
use std::{path::Path};
use tracing::{trace};
use triedb::{
    account::Account as TrieDbAccount,
    path::{AddressPath, StoragePath},
    Database as TrieDbDatabase,
};
#[derive(Debug)]
pub struct TrieExtDatabase {
    pub inner: TrieDbDatabase,
}

impl TrieExtDatabase {
    pub fn new(db_path: impl AsRef<Path>) -> Self {
        let db_path = db_path.as_ref();
        let db = TrieDbDatabase::create_new(db_path).unwrap();
        Self { inner: db }
    }
}

/// `StateRoot` is used to compute the root node of a state trie.
#[derive(Debug)]
pub struct StateRootTrieDb<H> {
    /// The factory for hashed cursors.
    pub hashed_cursor_factory: H,
    pub db: TrieExtDatabase,
}

impl<H> StateRootTrieDb<H> {
    /// Creates [`StateRootTrieDb`] with
    pub fn new(hashed_cursor_factory: H, db: TrieExtDatabase) -> Self {
        Self { hashed_cursor_factory, db }
    }
}
impl<H> StateRootTrieDb<H>
where
    H: HashedCursorFactory + Clone,
{
    pub fn calculate_commit(self) -> Result<B256, StateRootError> {
        trace!(target: "trie::state_root", "calculating state root");
        let mut acct_cursor = self.hashed_cursor_factory.hashed_account_cursor()?;
        let mut tx = self.db.inner.begin_rw().unwrap();
        let mut account_entry = acct_cursor.next().unwrap();
        while let Some((hashed_address, account)) = account_entry {
            let nibbles = Nibbles::unpack(hashed_address);
            let address_path = AddressPath::new(nibbles);

            let triedb_account = TrieDbAccount {
                nonce: account.nonce,
                balance: account.balance,
                code_hash: account.bytecode_hash.unwrap_or(KECCAK_EMPTY),
                storage_root: EMPTY_ROOT_HASH,
            };
            tx.set_account(address_path.clone(), Some(triedb_account)).unwrap();

            let mut storage_cursor =
                self.hashed_cursor_factory.hashed_storage_cursor(hashed_address)?;

            let mut storage_entry = storage_cursor.seek(B256::ZERO)?;
            while let Some((hashed_storage_key, storage_value)) = storage_entry {
                let storage_path = StoragePath::for_address_path_and_slot_hash(
                    address_path.clone(),
                    Nibbles::unpack(hashed_storage_key),
                );
                tx.set_storage_slot(storage_path, Some(storage_value)).unwrap();

                storage_entry = storage_cursor.next()?;
            }

            account_entry = acct_cursor.next()?;
        }
        tx.commit().unwrap();
        Ok(self.db.inner.state_root())
    }
}
