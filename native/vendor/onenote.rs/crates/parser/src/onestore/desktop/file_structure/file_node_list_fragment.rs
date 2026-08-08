use super::parse_context::ParseContext;
use crate::errors::ErrorKind;
use crate::errors::Result;
use crate::onestore::desktop::common::FileChunkReference64x32;
use crate::onestore::desktop::file_node::FileNode;
use crate::onestore::desktop::file_node::FileNodeData;
use crate::onestore::desktop::parse::Parse;

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub(crate) struct FileNodeListFragment {
    pub(crate) header: FileNodeListHeader,
    pub(crate) file_nodes: Vec<FileNode>,
    pub(crate) next_fragment: FileChunkReference64x32,
    pub(crate) footer: u64,
}

impl FileNodeListFragment {
    pub(crate) fn parse(
        reader: crate::Reader,
        context: &mut ParseContext,
        size: usize,
    ) -> Result<Self> {
        let header = FileNodeListHeader::parse(reader)?;
        let mut file_nodes: Vec<FileNode> = Vec::new();
        let mut file_node_size: usize = 0;

        let remaining_0 = reader.remaining();

        // Sometimes, the node count is specified externally
        let mut maximum_node_count = context.get_file_node_count(&header).unwrap_or({
            log::warn!("No node count found.");
            usize::MAX
        });

        while size - 36 - file_node_size >= 4 && maximum_node_count > 0 {
            let file_node = FileNode::parse(reader, context)?;
            file_node_size += file_node.size;
            let is_terminator = matches!(file_node.fnd, FileNodeData::ChunkTerminatorFND);

            if !matches!(
                file_node.fnd,
                FileNodeData::ChunkTerminatorFND | FileNodeData::Null
            ) {
                maximum_node_count -= 1;
            }
            if !matches!(file_node.fnd, FileNodeData::Null) {
                file_nodes.push(file_node);
            }

            let consumed = remaining_0 - reader.remaining();
            if consumed != file_node_size {
                return Err(ErrorKind::MalformedOneNoteFileData(
                    format!(
                        "FileNodeListFragment size accounting mismatch: reader consumed {consumed} bytes, declared sizes summed to {file_node_size}"
                    )
                    .into(),
                )
                .into());
            }

            // A ChunkTerminatorFND ends the node sequence. What follows, up to
            // `next_fragment`, is padding that OneNote does not zero — read on
            // and stale bytes decode as a plausible FileNode header.
            if is_terminator {
                break;
            }
        }

        context.update_remaining_nodes_in_fragment(&header, maximum_node_count);

        let padding_length = size - 36 - file_node_size;
        reader.advance(padding_length)?;

        let next_fragment = FileChunkReference64x32::parse(reader)?;

        let footer = reader.get_u64()?;
        if footer != 0x8BC215C38233BA4B {
            return Err(ErrorKind::MalformedOneStoreData(
                format!("Invalid footer: {:#0x}", footer).into(),
            )
            .into());
        }

        Ok(Self {
            header,
            file_nodes,
            next_fragment,
            footer,
        })
    }
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub(crate) struct FileNodeListHeader {
    magic: u64,
    pub(crate) file_node_list_id: u32,
    pub(crate) n_fragment_sequence: u32,
}

impl Parse for FileNodeListHeader {
    fn parse(reader: crate::Reader) -> Result<Self> {
        let magic = u64::parse(reader)?;
        if magic != 0xA4567AB1F5F7F4C4 {
            return Err(ErrorKind::ParseValidationFailed(
                "Failed to validate: magic == 0xA4567AB1F5F7F4C4".into(),
            )
            .into());
        }

        let file_node_list_id = u32::parse(reader)?;
        if file_node_list_id < 0x0010 {
            log::warn!(
                "FileNodeListHeader: file_node_list_id {:#x} is below spec minimum 0x10",
                file_node_list_id
            );
        }

        let n_fragment_sequence = u32::parse(reader)?;

        Ok(Self {
            magic,
            file_node_list_id,
            n_fragment_sequence,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::onestore::desktop::common::FileChunkReference;
    use crate::reader::Reader;

    const CHUNK_TERMINATOR_FND: u32 = 0x8000_10FF;

    /// A fragment holding a single ChunkTerminatorFND followed by `padding`
    /// bytes, then the trailer.
    fn fragment(padding: &[u8]) -> Vec<u8> {
        let mut data = Vec::new();
        data.extend_from_slice(&0xA456_7AB1_F5F7_F4C4u64.to_le_bytes());
        data.extend_from_slice(&0x10u32.to_le_bytes()); // file_node_list_id
        data.extend_from_slice(&0u32.to_le_bytes()); // n_fragment_sequence
        data.extend_from_slice(&CHUNK_TERMINATOR_FND.to_le_bytes());
        data.extend_from_slice(padding);
        data.extend_from_slice(&u64::MAX.to_le_bytes()); // next_fragment.stp (nil)
        data.extend_from_slice(&0u32.to_le_bytes()); // next_fragment.cb
        data.extend_from_slice(&0x8BC2_15C3_8233_BA4Bu64.to_le_bytes()); // footer
        data
    }

    fn parse(data: &[u8]) -> Result<FileNodeListFragment> {
        FileNodeListFragment::parse(&mut Reader::new(data), &mut ParseContext::new(), data.len())
    }

    /// OneNote does not zero the bytes between a ChunkTerminatorFND and
    /// `nextFragment`, so leftovers there can decode as a plausible FileNode
    /// header. The terminator ends the sequence — those bytes are padding.
    #[test]
    fn stops_at_chunk_terminator_with_stale_padding() {
        // Decodes as a node of unknown type declaring 81 bytes, far more than
        // the fragment has left.
        let data = fragment(&[0xEF, 0x44, 0x81, 0x00, 0x00, 0x00]);

        let fragment = parse(&data).unwrap();

        assert_eq!(fragment.file_nodes.len(), 1);
        assert!(matches!(
            fragment.file_nodes[0].fnd,
            FileNodeData::ChunkTerminatorFND
        ));
        assert!(fragment.next_fragment.is_fcr_nil());
    }

    #[test]
    fn stops_at_chunk_terminator_without_padding() {
        let data = fragment(&[]);

        let fragment = parse(&data).unwrap();

        assert_eq!(fragment.file_nodes.len(), 1);
        assert!(matches!(
            fragment.file_nodes[0].fnd,
            FileNodeData::ChunkTerminatorFND
        ));
    }
}
