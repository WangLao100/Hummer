import { Hummer, View, Text, Scroller } from '@hummer/hummer-front'
import { Style } from '../../common/CommonStyle'
import { Color } from '../../common/CommonColor'

class RootView extends Scroller {
    contentView: View;

    constructor() {
        super();
        this.style = {
            ...Style.FullParentStyle,
            ...Style.CenterStyle,
            backgroundColor: Color.white,
        }

        this.showPriceFlag();
    }

    /**
     * 价格居中 + 小标签
     */
    showPriceFlag() {
        let layout = new View();
        layout.style = {
            width: '100%',
            height: 60,
            flexDirection: 'row',
            justifyContent: 'center',
            backgroundColor: Color.hm_green,
        }

        let textView = new Text();
        textView.text = "￥88.88";
        textView.style = {
            fontSize: 30,
            color: Color.black,
        }

        let flagLayout = new View();

        let flagView = new Text();
        flagView.text = '优惠价'
        flagView.style = {
            position: 'absolute',
            height: 16,
            minWidth: 16,
            marginTop: 6,
            marginLeft: -12,
            padding: 4,
            backgroundColor: Color.red,
            borderRadius: 6,
            textAlign: 'center',
            fontSize: 10,
            color: '#FFFFFF',
        }

        flagLayout.appendChild(flagView);
        layout.appendChild(textView);
        layout.appendChild(flagLayout);
        this.appendChild(layout);
    }
}

Hummer.render(new RootView());