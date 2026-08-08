use crate::Reader;
use crate::onestore::desktop::file_node::FileNodeDataRef;
use crate::onestore::desktop::file_node::shared::{
    ObjectDeclarationNode, ParseWithRef, read_property_set,
};
use crate::onestore::shared::compact_id::CompactId;
use crate::onestore::shared::jcid::JcId;
use crate::onestore::shared::object_prop_set::ObjectPropSet;

/// Revision nodes carry no JCID field. As in the rest of this legacy
/// ref-counted family `jci` is fixed at 0x1, and they always carry a property
/// set, so IsPropertySet is set. See [\[MS-ONESTORE\] 2.6.14] and
/// `ObjectDeclarationWithRefCountBody::id`.
///
/// [\[MS-ONESTORE\] 2.6.14]: https://docs.microsoft.com/en-us/openspecs/office_file_formats/ms-onestore/388c266c-08e4-4ea4-af0e-5e2c5d1b995c
const REVISED_OBJECT_JC_ID: JcId = JcId(0x1 | 0x20000);

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub(crate) struct ObjectRevisionWithRefCountFNDX {
    oid: CompactId,
    f_has_oid_references: bool,
    f_has_osid_references: bool,
    property_set: ObjectPropSet,
    c_ref: u8,
}

impl<'a> ParseWithRef<'a> for ObjectRevisionWithRefCountFNDX {
    fn parse(reader: Reader, data_ref: &FileNodeDataRef) -> crate::errors::Result<Self> {
        let property_set = read_property_set(reader, data_ref)?;
        let oid = CompactId::parse(reader)?;
        let metadata = reader.get_u8()?;
        Ok(Self {
            oid,
            f_has_oid_references: metadata & 0x1 > 0,
            f_has_osid_references: metadata & 0x2 > 0,
            c_ref: (metadata & 0b1111_1100) >> 2,
            property_set,
        })
    }
}

impl ObjectDeclarationNode for ObjectRevisionWithRefCountFNDX {
    fn id(&self) -> JcId {
        REVISED_OBJECT_JC_ID
    }

    fn compact_id(&self) -> CompactId {
        self.oid
    }

    fn props(&self) -> Option<&ObjectPropSet> {
        Some(&self.property_set)
    }
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub(crate) struct ObjectRevisionWithRefCount2FNDX {
    oid: CompactId,
    f_has_oid_references: bool,
    f_has_osid_references: bool,
    property_set: ObjectPropSet,
    c_ref: u32,
}

impl<'a> ParseWithRef<'a> for ObjectRevisionWithRefCount2FNDX {
    fn parse(reader: Reader, data_ref: &FileNodeDataRef) -> crate::errors::Result<Self> {
        let property_set = read_property_set(reader, data_ref)?;
        let oid = CompactId::parse(reader)?;
        let metadata = reader.get_u32()?;
        Ok(Self {
            oid,
            f_has_oid_references: metadata & 0x1 > 0,
            f_has_osid_references: metadata & 0x2 > 0,
            c_ref: reader.get_u32()?,
            property_set,
        })
    }
}

impl ObjectDeclarationNode for ObjectRevisionWithRefCount2FNDX {
    fn id(&self) -> JcId {
        REVISED_OBJECT_JC_ID
    }

    fn compact_id(&self) -> CompactId {
        self.oid
    }

    fn props(&self) -> Option<&ObjectPropSet> {
        Some(&self.property_set)
    }
}
