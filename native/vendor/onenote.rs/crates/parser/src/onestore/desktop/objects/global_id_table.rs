use std::collections::HashMap;

use crate::errors::Result;
use crate::fsshttpb::data::exguid::ExGuid;
use crate::onestore::desktop::file_node::FileNodeData;
use crate::onestore::desktop::file_structure::FileNodeDataIterator;
use crate::onestore::desktop::objects::id_mapping::IdMapping;
use crate::onestore::shared::compact_id::CompactId;
use crate::shared::guid::Guid;

/// Lower-level structure for mapping local `CompactId`s to global `ExGuid`s. Applies to a
/// particular region of a OneStore file.
///
/// In `.onetoc2` files, `GlobalIdTable`s may depend on other `GlobalIdTable`s.
///
/// See [\[MS-ONESTORE\] 2.1.3](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-onestore/a243bd78-6cfd-4e18-96c7-e8c2095ce6b0)
#[derive(Debug, Clone)]
pub(crate) struct GlobalIdTable {
    pub(crate) id_map: IdMapping,
    /// Only used in .onetoc2 files
    _reference_map: IdReferenceMapping,
}

impl GlobalIdTable {
    pub(crate) fn try_parse(
        iterator: &mut FileNodeDataIterator,
        dependency: Option<&GlobalIdTable>,
    ) -> Result<Option<Self>> {
        let next = iterator.peek();

        match next {
            Some(
                FileNodeData::GlobalIdTableStart2FND | FileNodeData::GlobalIdTableStartFNDX(_),
            ) => Ok(Some(GlobalIdTable::parse(iterator, dependency)?)),
            _ => Ok(None),
        }
    }

    /// Resolve an index against the dependency revision's table, which
    /// `GlobalIdTableEntry2FNDX` / `GlobalIdTableEntry3FNDX` copy entries from.
    fn copy_from_dependency(dependency: Option<&GlobalIdTable>, index: u32) -> Result<Guid> {
        dependency
            .and_then(|table| table.id_map.get_guid(index))
            .ok_or_else(|| {
                onestore_parse_error!(
                    "Global ID table entry copies index {} from the dependency revision, \
                     which has no such entry",
                    index
                )
                .into()
            })
    }

    fn parse(
        iterator: &mut FileNodeDataIterator,
        dependency: Option<&GlobalIdTable>,
    ) -> Result<Self> {
        // Skip the start node
        iterator.next();

        let mut id_map = IdMapping::new();
        let mut reference_map = IdReferenceMapping::new();

        for node in iterator {
            match node {
                FileNodeData::GlobalIdTableEndFNDX => {
                    break;
                }
                FileNodeData::GlobalIdTableEntryFNDX(entry) => {
                    id_map.add_mapping(entry.index, entry.guid);
                }
                FileNodeData::GlobalIdTableEntry2FNDX(entry) => {
                    // Copies a single entry from the dependency revision's table.
                    let guid = Self::copy_from_dependency(dependency, entry.i_index_map_from)?;
                    id_map.add_mapping(entry.i_index_map_to, guid);

                    reference_map
                        .parent_references
                        .insert(entry.i_index_map_from, entry.i_index_map_to);
                }
                FileNodeData::GlobalIdTableEntry3FNDX(entry) => {
                    // Copies a run of entries from the dependency revision's table.
                    for offset in 0..entry.c_entries_to_copy {
                        let from = entry.i_index_copy_from_start + offset;
                        let guid = Self::copy_from_dependency(dependency, from)?;
                        id_map.add_mapping(entry.i_index_copy_to_start + offset, guid);

                        reference_map
                            .parent_references
                            .insert(from, entry.i_index_copy_to_start + offset);
                    }
                }
                FileNodeData::UnknownNode(_node) => {
                    log::warn!(
                        "Unknown node {:?} skipped while parsing global ID table.",
                        node
                    );
                }
                _ => {
                    return Err(onestore_parse_error!(
                        "Unexpected node ({:?}) encountered while parsing global ID table",
                        node
                    )
                    .into());
                }
            }
        }

        Ok(Self {
            id_map,
            _reference_map: reference_map,
        })
    }

    pub(crate) fn resolve_id(&self, id: &CompactId) -> Result<ExGuid> {
        self.id_map.resolve_id(id)
    }
}

impl Default for GlobalIdTable {
    fn default() -> Self {
        Self {
            id_map: IdMapping::new(),
            _reference_map: IdReferenceMapping::new(),
        }
    }
}

#[derive(Clone)]
struct IdReferenceMapping {
    /// Maps from indexes in dependency revisions to indexes in the current revision.
    parent_references: HashMap<u32, u32>,
}

impl std::fmt::Debug for IdReferenceMapping {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[IdReferenceMapping]")
    }
}

impl IdReferenceMapping {
    fn new() -> Self {
        Self {
            parent_references: HashMap::new(),
        }
    }
}
